import Foundation
import CommonCrypto
import SQLite3
import Security
import LocalAuthentication

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
    
    public func fetch(forceRefresh: Bool = false, completion: @escaping (Result<ClaudeState, Error>) -> Void) {
        if forceRefresh {
            ClaudeKeyChainHelper.resetKeyCache()
        }
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
            fetchedLimits = Self.parseUsageLimits(data)
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
        
        return ClaudeState(account: account, limits: fetchUsageWithOAuth(), isConnected: true)
    }
    
    /// Parses a usage payload (`five_hour`, `seven_day`, ...) shared by the claude.ai and OAuth endpoints.
    static func parseUsageLimits(_ data: Data?) -> ClaudeUsageLimits? {
        guard let data = data,
              let usage = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        
        let fhObj = usage["five_hour"] as? [String: Any]
        let sdObj = usage["seven_day"] as? [String: Any]
        let snObj = usage["seven_day_sonnet"] as? [String: Any]
        let soObj = usage["seven_day_opus"] as? [String: Any]
        let extraObj = usage["extra_usage"] as? [String: Any]
        
        guard fhObj != nil || sdObj != nil || snObj != nil else { return nil } // Free tier returns null limits
        
        func remaining(_ util: Double?) -> Int? {
            util.map { max(0, min(100, 100 - Int(round($0)))) }
        }
        let fhRemaining = remaining(fhObj?["utilization"] as? Double ?? 0.0) ?? 100
        let sdRemaining = remaining(sdObj?["utilization"] as? Double ?? 0.0) ?? 100
        
        return ClaudeUsageLimits(
            fiveHourRemainingPercent: fhRemaining,
            fiveHourUsedPercent: 100 - fhRemaining,
            fiveHourResetTime: parseDate(fhObj?["resets_at"]),
            weeklyRemainingPercent: sdRemaining,
            weeklyUsedPercent: 100 - sdRemaining,
            weeklyResetTime: parseDate(sdObj?["resets_at"]),
            sonnetRemainingPercent: remaining(snObj?["utilization"] as? Double),
            opusRemainingPercent: remaining(soObj?["utilization"] as? Double),
            extraUsagePercent: remaining(extraObj?["utilization"] as? Double),
            lastUpdated: Date()
        )
    }
    
    private var oauthRetryAfter = Date.distantPast
    private var lastGoodLimits: ClaudeUsageLimits?
    private var lastGoodAt = Date.distantPast
    /// Mirrors the user's refresh interval (seconds; 0 = manual, every fetch goes through).
    public var usagePollInterval: TimeInterval = 60
    private let rateLimitBackoff: TimeInterval = 60     // floor after a 429 (the endpoint sends Retry-After: 0)
    private var staleGrace: TimeInterval { max(900, usagePollInterval * 3) }  // keep last good numbers through brief failures
    
    /// Fetches usage with the Claude Code OAuth token. The token is only ever sent as a Bearer
    /// header to https://api.anthropic.com (HTTPS); it is never logged, stored, or sent elsewhere.
    /// The refresh token is never read or used: when the access token expires we simply fail
    /// and pick up the new token once Claude Code refreshes it in the Keychain.
    /// Requests follow the user's refresh interval; the last good result is reused for up to `staleGrace`, after which nil
    /// (the "Connection Lost" state) is returned.
    private func fetchUsageWithOAuth() -> ClaudeUsageLimits? {
        if Date() >= oauthRetryAfter {
            if let limits = requestUsage() {
                lastGoodLimits = limits
                lastGoodAt = Date()
                oauthRetryAfter = Date().addingTimeInterval(usagePollInterval)
            }
        }
        return Date().timeIntervalSince(lastGoodAt) <= staleGrace ? lastGoodLimits : nil
    }
    
    private func requestUsage() -> ClaudeUsageLimits? {
        guard let token = ClaudeKeyChainHelper.getClaudeCodeOAuthToken() else { return nil }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        
        let sem = DispatchSemaphore(value: 0)
        var limits: ClaudeUsageLimits? = nil
        session.dataTask(with: req) { [weak self] data, resp, _ in
            defer { sem.signal() }
            guard let http = resp as? HTTPURLResponse else { return }
            if http.statusCode == 429, let ra = http.value(forHTTPHeaderField: "Retry-After"), let secs = Double(ra) {
                self?.oauthRetryAfter = Date().addingTimeInterval(max(secs, self?.rateLimitBackoff ?? 60))
            }
            guard http.statusCode == 200 else { return }
            limits = Self.parseUsageLimits(data)
        }.resume()
        sem.wait()
        return limits
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
    private static var cachedSafeStorageKey: [UInt8]?
    private static var hasAttemptedSafeStorageKey = false

    static func getSafeStorageKey() -> [UInt8]? {
        if hasAttemptedSafeStorageKey {
            return cachedSafeStorageKey
        }
        
        let context = LAContext()
        context.interactionNotAllowed = true
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Safe Storage",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let pass = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pass.isEmpty else {
            hasAttemptedSafeStorageKey = true
            return nil
        }
        
        var derivedKey = [UInt8](repeating: 0, count: 16)
        let salt = "saltysalt"
        let cryptStatus = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            pass, pass.utf8.count,
            salt, salt.utf8.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
            1003,
            &derivedKey, 16
        )
        if cryptStatus == kCCSuccess {
            cachedSafeStorageKey = derivedKey
            hasAttemptedSafeStorageKey = true
            return derivedKey
        }
        hasAttemptedSafeStorageKey = true
        return nil
    }
    
    /// Reads the Claude Code OAuth access token from the macOS Keychain (local only).
    static func getClaudeCodeOAuthToken() -> String? {
        let context = LAContext()
        context.interactionNotAllowed = true
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        if let expiresAt = oauth["expiresAt"] as? Double, Date(timeIntervalSince1970: expiresAt / 1000) < Date() {
            return nil
        }
        return token
    }
    
    static func getCookie(name: String, key: [UInt8]) -> String? {
        let cookiePath = NSHomeDirectory() + "/Library/Application Support/Claude/Cookies"
        var db: OpaquePointer?
        guard sqlite3_open_v2(cookiePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
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
    
    static func resetKeyCache() {
        cachedSafeStorageKey = nil
        hasAttemptedSafeStorageKey = false
    }
}
