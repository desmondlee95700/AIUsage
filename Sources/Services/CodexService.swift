import Foundation

public struct CodexPayload {
    public let rateLimits: CodexRateLimitsResponse?
    public let account: CodexAccountInfo?
    public let usage: CodexUsageSummary?
}

public class CodexService {
    public static let shared = CodexService()
    
    private struct RPCResponse<T: Codable>: Codable {
        let id: Int?
        let result: T?
    }
    
    public init() {}

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

    public func fetch(completion: @escaping (Result<CodexPayload, Error>) -> Void) {
        guard let binaryPath = CodexDiscovery.findCodexBinary() else {
            completion(.failure(NSError(domain: "CodexService", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Codex runtime not found. Please verify ChatGPT.app is installed."
            ])))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = ["app-server"]
            
            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()

            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                completion(.failure(error))
                return
            }

            // `availableData` blocks until the child writes or exits, so the
            // deadline below is only checked between reads. Kill the child at
            // the deadline so a stalled response can't wedge this thread (and
            // QuotaService.isLoading with it) forever.
            let timeout: TimeInterval = 5.0
            Self.scheduleKill(of: process, after: timeout)

            // Prepare JSON-RPC payload requests
            let initMsg = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"AIUsage\",\"version\":\"1.0\"}}}\n"
            let rateLimitsMsg = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"account/rateLimits/read\",\"params\":{\"excludeResetCreditDetails\":false}}\n"
            let accountMsg = "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"account/read\",\"params\":{}}\n"
            let usageMsg = "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"account/usage/read\",\"params\":{}}\n"
            
            let combined = initMsg + rateLimitsMsg + accountMsg + usageMsg
            if let data = combined.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            
            var fetchedRateLimits: CodexRateLimitsResponse?
            var fetchedAccount: CodexAccountInfo?
            var fetchedUsage: CodexUsageSummary?
            
            // Ids of responses that arrived, whether or not they decoded, so a
            // payload we can't parse never leaves us waiting for more output.
            var answered = Set<Int>()
            var buffer = ""
            let handle = stdoutPipe.fileHandleForReading
            let deadline = Date().addingTimeInterval(timeout)

            while Date() < deadline {
                // If we got all 3 responses, we can stop reading
                if answered.count == 3 {
                    break
                }

                // Empty data means EOF: the child exited or was terminated above
                let chunk = handle.availableData
                if chunk.isEmpty {
                    break
                }

                if let str = String(data: chunk, encoding: .utf8) {
                    buffer += str
                    var lines = buffer.components(separatedBy: "\n")
                    buffer = lines.removeLast() // Keep trailing partial line

                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) else { continue }

                        // Notifications carry no id and server requests carry a
                        // method, so neither matches one of our responses
                        guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                              json["method"] == nil,
                              let id = json["id"] as? Int else { continue }

                        // Check which response it is
                        switch id {
                        case 2:
                            answered.insert(id)
                            if let resp = try? JSONDecoder().decode(RPCResponse<CodexRateLimitsResponse>.self, from: lineData) {
                                fetchedRateLimits = resp.result
                            }
                        case 3:
                            answered.insert(id)
                            if let resp = try? JSONDecoder().decode(RPCResponse<CodexAccountResponse>.self, from: lineData) {
                                fetchedAccount = resp.result?.account
                            }
                        case 4:
                            answered.insert(id)
                            if let resp = try? JSONDecoder().decode(RPCResponse<CodexUsageResponse>.self, from: lineData) {
                                fetchedUsage = resp.result?.summary
                            }
                        default:
                            break
                        }
                    }
                }
            }
            
            if process.isRunning {
                process.terminate()
            }
            
            if let limits = fetchedRateLimits {
                let payload = CodexPayload(
                    rateLimits: limits,
                    account: fetchedAccount,
                    usage: fetchedUsage
                )
                completion(.success(payload))
            } else {
                completion(.failure(NSError(domain: "CodexService", code: 504, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to read rate limits from Codex runtime."
                ])))
            }
        }
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
    
    public func consumeResetCredit(completion: @escaping (Result<ConsumeResetCreditOutcome, Error>) -> Void) {
        guard let binaryPath = CodexDiscovery.findCodexBinary() else {
            completion(.failure(NSError(domain: "CodexService", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Codex runtime not found. Please verify ChatGPT.app is installed."
            ])))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = ["app-server"]
            
            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()

            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                completion(.failure(error))
                return
            }

            // Same blocking-read guard as fetch()
            let timeout: TimeInterval = 6.0
            Self.scheduleKill(of: process, after: timeout)

            let initMsg = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"AIUsage\",\"version\":\"1.0\"}}}\n"
            let idempotencyKey = UUID().uuidString.lowercased()
            let consumeMsg = "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"account/rateLimitResetCredit/consume\",\"params\":{\"idempotencyKey\":\"\(idempotencyKey)\"}}\n"
            
            let combined = initMsg + consumeMsg
            if let data = combined.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            
            var outcome: ConsumeResetCreditOutcome?
            var serverError: String?
            
            var buffer = ""
            let handle = stdoutPipe.fileHandleForReading
            let deadline = Date().addingTimeInterval(timeout)

            while Date() < deadline && outcome == nil && serverError == nil {
                // Empty data means EOF: the child exited or was terminated above
                let chunk = handle.availableData
                if chunk.isEmpty {
                    break
                }

                if let str = String(data: chunk, encoding: .utf8) {
                    buffer += str
                    var lines = buffer.components(separatedBy: "\n")
                    buffer = lines.removeLast()
                    
                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) else { continue }
                        
                        guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                              json["method"] == nil,
                              json["id"] as? Int == 5 else { continue }

                        if let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
                            serverError = msg
                        } else if let res = json["result"] as? [String: Any], let rawOutcome = res["outcome"] as? String {
                            outcome = ConsumeResetCreditOutcome(rawValue: rawOutcome) ?? .unknown
                        }
                    }
                }
            }
            
            if process.isRunning {
                process.terminate()
            }
            
            if let outcome = outcome {
                completion(.success(outcome))
            } else if let errorMsg = serverError {
                completion(.failure(NSError(domain: "CodexService", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: errorMsg
                ])))
            } else {
                completion(.failure(NSError(domain: "CodexService", code: 504, userInfo: [
                    NSLocalizedDescriptionKey: "Reset request timed out."
                ])))
            }
        }
    }
}
