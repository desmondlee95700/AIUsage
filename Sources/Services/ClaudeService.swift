import Foundation
import CommonCrypto
import SQLite3

public final class ClaudeService {
    public static let shared = ClaudeService()
    
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 6.0
        self.session = URLSession(configuration: config)
    }
    
    public struct ClaudeState {
        public let account: ClaudeAccountInfo?
        public let limits: ClaudeUsageLimits?
        public let isConnected: Bool
        
        public init(account: ClaudeAccountInfo?, limits: ClaudeUsageLimits?, isConnected: Bool) {
            self.account = account
            self.limits = limits
            self.isConnected = isConnected
        }
    }
    
    public func fetch(completion: @escaping (Result<ClaudeState, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // 1. Try real desktop session via Claude Safe Storage cookie
            if let activeDesktopState = self.fetchFromDesktopSession() {
                completion(.success(activeDesktopState))
                return
            }
            
            // 2. Fall back to local CLI config if desktop session not found
            if let cliState = self.fetchFromClaudeJson() {
                completion(.success(cliState))
                return
            }
            
            completion(.failure(NSError(domain: "ClaudeService", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "No active Claude account detected. Please launch and log in to Claude.app."
            ])))
        }
    }
    
    // MARK: - Live Desktop Session Fetcher (Real Account & Real Quotas)
    
    private func fetchFromDesktopSession() -> ClaudeState? {
        guard let key = ClaudeKeyChainHelper.getSafeStorageKey(),
              let sessionKey = ClaudeKeyChainHelper.getCookie(name: "sessionKey", key: key) else {
            return nil
        }
        
        let lastOrgFromCookie = ClaudeKeyChainHelper.getCookie(name: "lastActiveOrg", key: key)
        
        // 1. Fetch organization profile
        let orgsUrl = URL(string: "https://claude.ai/api/organizations")!
        var orgsReq = URLRequest(url: orgsUrl)
        orgsReq.setValue("sessionKey=" + sessionKey, forHTTPHeaderField: "Cookie")
        orgsReq.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        let semOrgs = DispatchSemaphore(value: 0)
        var fetchedOrg: [String: Any]? = nil
        
        session.dataTask(with: orgsReq) { data, _, _ in
            defer { semOrgs.signal() }
            guard let data = data,
                  let orgsList = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  !orgsList.isEmpty else { return }
            
            if let targetUuid = lastOrgFromCookie,
               let match = orgsList.first(where: { ($0["uuid"] as? String) == targetUuid }) {
                fetchedOrg = match
            } else {
                fetchedOrg = orgsList.first
            }
        }.resume()
        semOrgs.wait()
        
        guard let org = fetchedOrg else {
            return nil
        }
        
        let orgUuid = org["uuid"] as? String ?? (lastOrgFromCookie ?? "")
        let rawOrgName = org["name"] as? String ?? ""
        let planType = org["analytics_subscription_plan"] as? String ?? (org["billing_type"] as? String ?? "claude_free")
        let billingType = org["billing_type"] as? String ?? "none"
        let rateLimitTier = org["rate_limit_tier"] as? String
        let createdAt = org["created_at"] as? String
        
        // Extract display email and name cleanly from org name (e.g. "d3smond95@gmail.com's Organization")
        let extractedEmail: String = {
            if let atRange = rawOrgName.range(of: "@") {
                let prefix = rawOrgName[..<atRange.upperBound]
                let suffix = rawOrgName[atRange.upperBound...]
                let start = prefix.split(separator: " ").last ?? prefix
                let end = suffix.split(separator: "'").first?.split(separator: " ").first ?? suffix
                let candidate = String(start + end)
                if candidate.contains("@") && candidate.contains(".") {
                    return candidate
                }
            }
            return rawOrgName
        }()
        
        let account = ClaudeAccountInfo(
            accountUuid: orgUuid,
            emailAddress: extractedEmail,
            displayName: extractedEmail.split(separator: "@").first.map(String.init) ?? rawOrgName,
            organizationUuid: orgUuid,
            organizationType: planType,
            billingType: billingType,
            hasExtraUsageEnabled: false,
            organizationRateLimitTier: rateLimitTier,
            subscriptionCreatedAt: createdAt
        )
        
        // 2. Fetch real rate limits usage
        guard !orgUuid.isEmpty else {
            return ClaudeState(account: account, limits: nil, isConnected: true)
        }
        
        let usageUrl = URL(string: "https://claude.ai/api/organizations/\(orgUuid)/usage")!
        var usageReq = URLRequest(url: usageUrl)
        usageReq.setValue("sessionKey=" + sessionKey, forHTTPHeaderField: "Cookie")
        usageReq.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        let semUsage = DispatchSemaphore(value: 0)
        var fetchedLimits: ClaudeUsageLimits? = nil
        
        session.dataTask(with: usageReq) { data, _, _ in
            defer { semUsage.signal() }
            guard let data = data,
                  let usage = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            
            let fhObj = usage["five_hour"] as? [String: Any]
            let sdObj = usage["seven_day"] as? [String: Any]
            let snObj = usage["seven_day_sonnet"] as? [String: Any]
            let soObj = usage["seven_day_opus"] as? [String: Any]
            let extraObj = usage["extra_usage"] as? [String: Any]
            
            let hasAnyLimits = fhObj != nil || sdObj != nil || snObj != nil
            guard hasAnyLimits else {
                // Free tier returns null limits
                return
            }
            
            let fhUtil = fhObj?["utilization"] as? Double ?? 0.0
            let sdUtil = sdObj?["utilization"] as? Double ?? 0.0
            let snUtil = snObj?["utilization"] as? Double
            let soUtil = soObj?["utilization"] as? Double
            let extraUtil = extraObj?["utilization"] as? Double
            
            let fhRemaining = max(0, min(100, 100 - Int(round(fhUtil))))
            let sdRemaining = max(0, min(100, 100 - Int(round(sdUtil))))
            let snRemaining = snUtil.map { max(0, min(100, 100 - Int(round($0)))) }
            let soRemaining = soUtil.map { max(0, min(100, 100 - Int(round($0)))) }
            let extraRemaining = extraUtil.map { max(0, min(100, 100 - Int(round($0)))) }
            
            let fhReset = Self.parseDate(fhObj?["resets_at"])
            let sdReset = Self.parseDate(sdObj?["resets_at"])
            
            fetchedLimits = ClaudeUsageLimits(
                fiveHourRemainingPercent: fhRemaining,
                fiveHourUsedPercent: 100 - fhRemaining,
                fiveHourResetTime: fhReset,
                weeklyRemainingPercent: sdRemaining,
                weeklyUsedPercent: 100 - sdRemaining,
                weeklyResetTime: sdReset,
                sonnetRemainingPercent: snRemaining,
                opusRemainingPercent: soRemaining,
                extraUsagePercent: extraRemaining,
                lastUpdated: Date()
            )
        }.resume()
        semUsage.wait()
        
        return ClaudeState(account: account, limits: fetchedLimits, isConnected: true)
    }
    
    // MARK: - Fallback Claude CLI ~/.claude.json
    
    private func fetchFromClaudeJson() -> ClaudeState? {
        let home = NSHomeDirectory()
        let claudeJsonURL = URL(fileURLWithPath: "\(home)/.claude.json")
        guard let data = try? Data(contentsOf: claudeJsonURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        guard let oauth = json["oauthAccount"] as? [String: Any] else {
            return nil
        }
        
        let accountUuid = oauth["accountUuid"] as? String
        let emailAddress = oauth["emailAddress"] as? String
        let displayName = oauth["displayName"] as? String
        let organizationUuid = oauth["organizationUuid"] as? String
        let organizationType = oauth["organizationType"] as? String
        let billingType = oauth["billingType"] as? String
        let hasExtraUsage = oauth["hasExtraUsageEnabled"] as? Bool
        let rateLimitTier = oauth["organizationRateLimitTier"] as? String
        let createdAt = oauth["subscriptionCreatedAt"] as? String
        
        let account = ClaudeAccountInfo(
            accountUuid: accountUuid,
            emailAddress: emailAddress,
            displayName: displayName,
            organizationUuid: organizationUuid,
            organizationType: organizationType,
            billingType: billingType,
            hasExtraUsageEnabled: hasExtraUsage,
            organizationRateLimitTier: rateLimitTier,
            subscriptionCreatedAt: createdAt
        )
        
        return ClaudeState(account: account, limits: nil, isConnected: true)
    }
    
    public static func parseDate(_ val: Any?) -> Date? {
        guard let val = val else { return nil }
        if let str = val as? String, !str.isEmpty {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = formatter.date(from: str) { return d }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: str)
        }
        if let num = val as? Double {
            return Date(timeIntervalSince1970: num > 1e11 ? num / 1000.0 : num)
        }
        return nil
    }
}

// MARK: - Keychain and Chromium Cookies Extractor

private struct ClaudeKeyChainHelper {
    static func getSafeStorageKey() -> [UInt8]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Safe Storage", "-w"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let pass = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !pass.isEmpty else { return nil }
            
            var derivedKey = [UInt8](repeating: 0, count: 16)
            let salt = "saltysalt"
            let status = CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                pass, pass.utf8.count,
                salt, salt.utf8.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                1003,
                &derivedKey, 16
            )
            return status == kCCSuccess ? derivedKey : nil
        } catch {
            return nil
        }
    }
    
    static func getCookie(name: String, key: [UInt8]) -> String? {
        let cookiePath = NSHomeDirectory() + "/Library/Application Support/Claude/Cookies"
        var db: OpaquePointer?
        guard sqlite3_open(cookiePath, &db) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        let query = "SELECT encrypted_value FROM cookies WHERE name = \"" + name + "\""
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            guard let blob = sqlite3_column_blob(stmt, 0) else { return nil }
            let count = Int(sqlite3_column_bytes(stmt, 0))
            let data = Data(bytes: blob, count: count)
            guard data.count > 35, data.prefix(3) == Data("v10".utf8) else { return nil }
            let cipherData = data.subdata(in: 3..<data.count)
            var decrypted = [UInt8](repeating: 0, count: cipherData.count + 16)
            var numBytesDecrypted: size_t = 0
            let iv = [UInt8](repeating: 0x20, count: 16)
            let status = CCCrypt(
                CCOperation(kCCDecrypt),
                CCAlgorithm(kCCAlgorithmAES),
                CCOptions(kCCOptionPKCS7Padding),
                key, 16,
                iv,
                cipherData.withUnsafeBytes { $0.baseAddress! }, cipherData.count,
                &decrypted, decrypted.count,
                &numBytesDecrypted
            )
            if status == kCCSuccess && numBytesDecrypted > 32 {
                let res = Data(decrypted.prefix(numBytesDecrypted))
                return String(data: res.subdata(in: 32..<res.count), encoding: .utf8)
            }
        }
        return nil
    }
}
