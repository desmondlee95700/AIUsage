import Foundation

public struct CodexPayload {
    public let rateLimits: CodexRateLimitsResponse?
    public let account: CodexAccountInfo?
    public let usage: CodexUsageSummary?
}

public final class CodexService {
    public static let shared = CodexService()

    private struct RPCResponse<T: Codable>: Codable {
        let id: Int?
        let result: T?
    }

    private struct RPCRequest {
        let id: Int
        let method: String
        let params: [String: Any]
    }

    public init() {}

    // MARK: - Public API

    public func fetch() async throws -> CodexPayload {
        try await runBlocking { Result { try Self.fetchBlocking() } }.get()
    }

    public func consumeResetCredit() async throws -> ConsumeResetCreditOutcome {
        try await runBlocking { Result { try Self.consumeResetCreditBlocking() } }.get()
    }

    // MARK: - App-server JSON-RPC

    /// Terminates `process` if it is still running after `timeout`, escalating
    /// to SIGKILL a second later in case SIGTERM is ignored. Ending the child
    /// closes its stdout, which unblocks any pending `availableData` read.
    private static func scheduleKill(of process: Process, after timeout: TimeInterval) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
            guard process.isRunning else { return }
            process.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
    }

    /// Splits complete newline-terminated lines off the front of `buffer`, leaving any partial line.
    /// Works on raw bytes so a read that ends inside a multi-byte UTF-8 character can't drop output.
    static func takeLines(from buffer: inout Data) -> [Data] {
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(Data(buffer[buffer.startIndex..<newline]))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        return lines
    }

    private static func codexBinary() throws -> String {
        guard let binaryPath = CodexDiscovery.findCodexBinary() else {
            throw NSError(domain: "CodexService", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Codex runtime not found. Please verify ChatGPT.app is installed."
            ])
        }
        return binaryPath
    }

    /// Launches `codex app-server`, sends `initialize` followed by `requests` as JSON-RPC lines, and
    /// returns the raw response line for each request id that answered. Stops once every request has
    /// answered, the child exits, or `timeout` passes. Blocks the calling thread.
    private static func exchange(_ requests: [RPCRequest], timeout: TimeInterval) throws -> [Int: Data] {
        let binaryPath = try codexBinary()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["app-server"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        // `availableData` blocks until the child writes or exits, so the
        // deadline below is only checked between reads. Kill the child at
        // the deadline so a stalled response can't wedge this thread (and
        // QuotaService.isLoading with it) forever.
        scheduleKill(of: process, after: timeout)

        let initialize = RPCRequest(id: 1, method: "initialize", params: [
            "clientInfo": ["name": "AIUsage", "version": AppVersion.current]
        ])
        var payload = Data()
        for request in [initialize] + requests {
            let message: [String: Any] = ["jsonrpc": "2.0", "id": request.id, "method": request.method, "params": request.params]
            payload.append(try JSONSerialization.data(withJSONObject: message))
            payload.append(0x0A)
        }
        stdinPipe.fileHandleForWriting.write(payload)

        let wanted = Set(requests.map(\.id))
        var responses: [Int: Data] = [:]
        var buffer = Data()
        let handle = stdoutPipe.fileHandleForReading
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline && responses.count < wanted.count {
            // Empty data means EOF: the child exited or was terminated above
            let chunk = handle.availableData
            if chunk.isEmpty {
                break
            }

            buffer.append(chunk)
            for lineData in takeLines(from: &buffer) where !lineData.isEmpty {
                // Notifications carry no id and server requests carry a
                // method, so neither matches one of our responses
                guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      json["method"] == nil,
                      let id = json["id"] as? Int,
                      wanted.contains(id) else { continue }
                // Recorded whether or not it decodes, so a payload we can't parse
                // never leaves us waiting for more output
                responses[id] = lineData
            }
        }
        return responses
    }

    // MARK: - Rate Limits

    private static func fetchBlocking() throws -> CodexPayload {
        let responses = try exchange([
            RPCRequest(id: 2, method: "account/rateLimits/read", params: ["excludeResetCreditDetails": false]),
            RPCRequest(id: 3, method: "account/read", params: [:]),
            RPCRequest(id: 4, method: "account/usage/read", params: [:])
        ], timeout: 5.0)

        func decode<T: Codable>(_ id: Int, as type: T.Type) -> T? {
            responses[id].flatMap { try? JSONDecoder().decode(RPCResponse<T>.self, from: $0) }?.result
        }

        guard let limits = decode(2, as: CodexRateLimitsResponse.self) else {
            throw NSError(domain: "CodexService", code: 504, userInfo: [
                NSLocalizedDescriptionKey: "Failed to read rate limits from Codex runtime."
            ])
        }
        return CodexPayload(
            rateLimits: limits,
            account: decode(3, as: CodexAccountResponse.self)?.account,
            usage: decode(4, as: CodexUsageResponse.self)?.summary
        )
    }

    // MARK: - Consume Rate Limit Reset Credit

    public enum ConsumeResetCreditOutcome: String {
        case reset = "reset"
        case nothingToReset = "nothing_to_reset"
        case noCredit = "no_credit"
        case alreadyRedeemed = "already_redeemed"
        case unknown = "unknown"

        public var isSuccess: Bool {
            self == .reset
        }

        public var userMessage: String {
            switch self {
            case .reset:
                return "Reset successfully applied! Your 5h and weekly limits have been restored."
            case .nothingToReset:
                return "Current limits still have more than 10% remaining. Resets can only be used when 10% or less remains."
            case .noCredit:
                return "No available reset credits found."
            case .alreadyRedeemed:
                return "This reset credit has already been redeemed."
            case .unknown:
                return "Reset request processed."
            }
        }
    }

    private static func consumeResetCreditBlocking() throws -> ConsumeResetCreditOutcome {
        let idempotencyKey = UUID().uuidString.lowercased()
        let responses = try exchange([
            RPCRequest(id: 5, method: "account/rateLimitResetCredit/consume", params: ["idempotencyKey": idempotencyKey])
        ], timeout: 6.0)

        guard let line = responses[5],
              let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw NSError(domain: "CodexService", code: 504, userInfo: [
                NSLocalizedDescriptionKey: "Reset request timed out."
            ])
        }
        if let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
            throw NSError(domain: "CodexService", code: 500, userInfo: [
                NSLocalizedDescriptionKey: msg
            ])
        }
        guard let res = json["result"] as? [String: Any], let rawOutcome = res["outcome"] as? String else {
            throw NSError(domain: "CodexService", code: 504, userInfo: [
                NSLocalizedDescriptionKey: "Reset request timed out."
            ])
        }
        return ConsumeResetCreditOutcome(rawValue: rawOutcome) ?? .unknown
    }
}
