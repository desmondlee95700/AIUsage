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
            let stderrPipe = Pipe()
            
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            
            do {
                try process.run()
            } catch {
                completion(.failure(error))
                return
            }
            
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
            
            var buffer = ""
            let handle = stdoutPipe.fileHandleForReading
            let deadline = Date().addingTimeInterval(5.0)
            
            while Date() < deadline {
                // If we got all 3 responses, we can stop reading
                if fetchedRateLimits != nil && fetchedAccount != nil && fetchedUsage != nil {
                    break
                }
                
                let chunk = handle.availableData
                if chunk.isEmpty {
                    Thread.sleep(forTimeInterval: 0.05)
                    continue
                }
                
                if let str = String(data: chunk, encoding: .utf8) {
                    buffer += str
                    var lines = buffer.components(separatedBy: "\n")
                    buffer = lines.removeLast() // Keep trailing partial line
                    
                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) else { continue }
                        
                        // Check which response it is
                        if trimmed.contains("\"id\":2") {
                            if let resp = try? JSONDecoder().decode(RPCResponse<CodexRateLimitsResponse>.self, from: lineData) {
                                fetchedRateLimits = resp.result
                            }
                        } else if trimmed.contains("\"id\":3") {
                            if let resp = try? JSONDecoder().decode(RPCResponse<CodexAccountResponse>.self, from: lineData) {
                                fetchedAccount = resp.result?.account
                            }
                        } else if trimmed.contains("\"id\":4") {
                            if let resp = try? JSONDecoder().decode(RPCResponse<CodexUsageResponse>.self, from: lineData) {
                                fetchedUsage = resp.result?.summary
                            }
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
            let stderrPipe = Pipe()
            
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            
            do {
                try process.run()
            } catch {
                completion(.failure(error))
                return
            }
            
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
            let deadline = Date().addingTimeInterval(6.0)
            
            while Date() < deadline && outcome == nil && serverError == nil {
                let chunk = handle.availableData
                if chunk.isEmpty {
                    Thread.sleep(forTimeInterval: 0.05)
                    continue
                }
                
                if let str = String(data: chunk, encoding: .utf8) {
                    buffer += str
                    var lines = buffer.components(separatedBy: "\n")
                    buffer = lines.removeLast()
                    
                    for line in lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) else { continue }
                        
                        if trimmed.contains("\"id\":5") {
                            if let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                                if let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
                                    serverError = msg
                                } else if let res = json["result"] as? [String: Any], let rawOutcome = res["outcome"] as? String {
                                    outcome = ConsumeResetCreditOutcome(rawValue: rawOutcome) ?? .unknown
                                }
                            }
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
