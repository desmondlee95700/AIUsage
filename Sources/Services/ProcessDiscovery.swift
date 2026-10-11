import Foundation
import AppKit

public struct DiscoveredServer: Equatable {
    public let pid: Int
    public let csrfToken: String
    public let port: Int
    public let sourceName: String
}

/// Accepts the Antigravity language server's self-signed certificate. Trust is only bypassed
/// for the loopback address; any other host gets the system's normal certificate validation.
public final class InsecureTrustDelegate: NSObject, URLSessionDelegate {
    public static let shared = InsecureTrustDelegate()
    
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           challenge.protectionSpace.host == "127.0.0.1",
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

public class ProcessDiscovery {
    private static let cacheLock = NSLock()
    private static var _cachedServer: DiscoveredServer?
    private static var cachedServer: DiscoveredServer? {
        get { cacheLock.lock(); defer { cacheLock.unlock() }; return _cachedServer }
        set { cacheLock.lock(); _cachedServer = newValue; cacheLock.unlock() }
    }
    
    /// One session for all loopback probes. Sessions retain their delegate until
    /// invalidated, so creating one per probe leaks.
    private static let probeSession = URLSession(
        configuration: .ephemeral,
        delegate: InsecureTrustDelegate.shared,
        delegateQueue: nil
    )
    
    public static func invalidateCache() {
        cachedServer = nil
    }
    
    public static var isAntigravityInstalled: Bool {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let candidatePaths = [
            "/Applications/Antigravity.app",
            "/Applications/Antigravity IDE.app",
            "\(home)/Applications/Antigravity.app",
            "\(home)/Applications/Antigravity IDE.app",
            "\(home)/.gemini/antigravity"
        ]
        for path in candidatePaths {
            if fileManager.fileExists(atPath: path) {
                return true
            }
        }
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.antigravity") != nil ||
           NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.antigravity-ide") != nil {
            return true
        }
        if cachedServer != nil || !findProcessCandidates().isEmpty {
            return true
        }
        return false
    }
    
    public static func discover(forceRefresh: Bool = false) -> DiscoveredServer? {
        // Callers verify the cached server by using it and call invalidateCache() on failure,
        // so there's no separate health-check request here.
        if !forceRefresh, let cached = cachedServer {
            return cached
        }
        
        let candidates = findProcessCandidates()
        for candidate in candidates {
            if let server = probeCandidate(candidate) {
                cachedServer = server
                return server
            }
        }
        
        return nil
    }
    
    private struct Candidate {
        let pid: Int
        let csrfToken: String
        let fullCommand: String
        let isApp: Bool
    }
    
    private static func findProcessCandidates() -> [Candidate] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "ps -A -o pid,args | grep '[l]anguage_server'"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            
            var list: [Candidate] = []
            let lines = output.components(separatedBy: "\n")
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                
                let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard parts.count >= 2, let pid = Int(parts[0]) else { continue }
                let command = String(parts[1])
                
                // Accepts both `--csrf_token VALUE` and `--csrf_token=VALUE`
                var token = ""
                if let range = command.range(of: "--csrf_token") {
                    var sub = command[range.upperBound...].trimmingCharacters(in: .whitespaces)
                    if sub.hasPrefix("=") {
                        sub.removeFirst()
                    }
                    token = sub.components(separatedBy: .whitespaces).first ?? ""
                }
                
                let isApp = command.contains("Antigravity.app") || command.contains("--app_data_dir antigravity")
                list.append(Candidate(pid: pid, csrfToken: token, fullCommand: command, isApp: isApp))
            }
            
            // Prioritize Antigravity desktop app over IDE extension
            list.sort { $0.isApp && !$1.isApp }
            return list
        } catch {
            return []
        }
    }
    
    private static func probeCandidate(_ candidate: Candidate) -> DiscoveredServer? {
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", "\(candidate.pid)"]
        
        let pipe = Pipe()
        lsof.standardOutput = pipe
        
        do {
            try lsof.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            lsof.waitUntilExit()
            
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            
            var ports: [Int] = []
            for line in output.components(separatedBy: "\n") {
                if let colonRange = line.range(of: ":", options: .backwards) {
                    let afterColon = line[colonRange.upperBound...]
                    let portStr = afterColon.components(separatedBy: .whitespaces).first ?? ""
                    if let port = Int(portStr), !ports.contains(port) {
                        ports.append(port)
                    }
                }
            }
            
            let sourceName = candidate.isApp ? "Antigravity App" : "Antigravity IDE"
    
            for port in ports {
                if testEndpoint(port: port, token: candidate.csrfToken) {
                    return DiscoveredServer(pid: candidate.pid, csrfToken: candidate.csrfToken, port: port, sourceName: sourceName)
                }
            }
        } catch {
            return nil
        }
        
        return nil
    }
    
    private static func testEndpoint(port: Int, token: String) -> Bool {
        guard let url = URL(string: "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary") else {
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 2.0
        
        var success = false
        let sem = DispatchSemaphore(value: 0)
        let task = probeSession.dataTask(with: request) { _, response, error in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                success = true
            }
            sem.signal()
        }
        task.resume()
        if sem.wait(timeout: .now() + 2.5) == .timedOut {
            // Don't read `success` while the callback may still write it
            task.cancel()
            sem.wait()
        }
        return success
    }
    
    public static func launchAntigravityApp() {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.path
        let candidatePaths = [
            "/Applications/Antigravity.app",
            "/Applications/Antigravity IDE.app",
            "\(home)/Applications/Antigravity.app",
            "\(home)/Applications/Antigravity IDE.app"
        ]
        for path in candidatePaths {
            if fileManager.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
                return
            }
        }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.antigravity") ??
                         NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.antigravity-ide") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
            return
        }
    }
}
