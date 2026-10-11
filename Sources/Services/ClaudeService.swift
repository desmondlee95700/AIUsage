import Foundation
import CommonCrypto
import SQLite3
import Security
import LocalAuthentication

/// An actor, so the pacing and last-good state below is only touched by one fetch at a time.
/// QuotaService never overlaps refreshes, so fetches don't interleave across their awaits in practice.
public actor ClaudeService {
    public static let shared = ClaudeService()
    
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 6.0
        self.session = URLSession(configuration: config)
    }
    
    public struct ClaudeState: Sendable {
        public let account: ClaudeAccountInfo?
        public let limits: ClaudeUsageLimits?
        public let isConnected: Bool
        
        public init(account: ClaudeAccountInfo?, limits: ClaudeUsageLimits?, isConnected: Bool) {
            self.account = account
            self.limits = limits
            self.isConnected = isConnected
        }
    }
    
    /// - Parameter pollInterval: The user's refresh interval in seconds (0 = manual); paces usage requests.
    public func fetch(forceRefresh: Bool = false, pollInterval: TimeInterval) async throws -> ClaudeState {
        usagePollInterval = pollInterval
        if forceRefresh {
            ClaudeKeyChainHelper.resetKeyCache()
        }
        
        // 1. Try real desktop session via Claude Safe Storage cookie
        if let activeDesktopState = await fetchFromDesktopSession() {
            return activeDesktopState
        }
        
        // 2. Fall back to local CLI config if desktop session not found
        if let cliState = await fetchFromClaudeJson() {
            return cliState
        }
        
        throw NSError(domain: "ClaudeService", code: 404, userInfo: [
            NSLocalizedDescriptionKey: "No active Claude account detected. Please launch and log in to Claude.app."
        ])
    }
    
    /// Sends `request`, returning nil on transport errors or non-HTTP responses.
    private func send(_ request: URLRequest) async -> (data: Data, response: HTTPURLResponse)? {
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        return (data, http)
    }
    
    /// Seconds to back off after a 429, or nil when `response` isn't one.
    private func retryAfter(_ response: HTTPURLResponse?) -> TimeInterval? {
        guard let response = response, response.statusCode == 429 else { return nil }
        let seconds = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 0
        return max(seconds, rateLimitBackoff)
    }
    
    // MARK: - Live Desktop Session Fetcher (Real Account & Real Quotas)
    
    private func fetchFromDesktopSession() async -> ClaudeState? {
        guard let key = ClaudeKeyChainHelper.getSafeStorageKey(),
              let sessionKey = ClaudeKeyChainHelper.getCookie(name: "sessionKey", key: key) else {
            return nil
        }
        
        // Within the pacing window, reuse the last account and limits instead of hitting claude.ai again
        if Date() < desktopRetryAfter, let account = lastDesktopAccount {
            return ClaudeState(account: account, limits: rememberLimits(nil), isConnected: true)
        }
        let requestStart = Date()
        
        let lastOrgFromCookie = ClaudeKeyChainHelper.getCookie(name: "lastActiveOrg", key: key)
        
        // 1. Fetch organization profile
        let orgsUrl = URL(string: "https://claude.ai/api/organizations")!
        var orgsReq = URLRequest(url: orgsUrl)
        orgsReq.setValue("sessionKey=" + sessionKey, forHTTPHeaderField: "Cookie")
        orgsReq.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        // An expired session returns an error object rather than a list, so this falls through to the CLI path
        guard let orgsData = await send(orgsReq)?.data,
              let orgsList = try? JSONSerialization.jsonObject(with: orgsData) as? [[String: Any]],
              let org = orgsList.first(where: { ($0["uuid"] as? String) == lastOrgFromCookie }) ?? orgsList.first else {
            return nil
        }
        
        let orgUuid = org["uuid"] as? String ?? (lastOrgFromCookie ?? "")
        let rawOrgName = org["name"] as? String ?? ""
        let planType = org["analytics_subscription_plan"] as? String ?? (org["billing_type"] as? String ?? "claude_free")
        let billingType = org["billing_type"] as? String ?? "none"
        let rateLimitTier = org["rate_limit_tier"] as? String
        let createdAt = org["created_at"] as? String
        
        // Extract display email and name cleanly from org name (e.g. "user@example.com's Organization")
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
        
        lastDesktopAccount = account
        
        // 2. Fetch real rate limits usage
        guard !orgUuid.isEmpty else {
            return ClaudeState(account: account, limits: nil, isConnected: true)
        }
        
        let usageUrl = URL(string: "https://claude.ai/api/organizations/\(orgUuid)/usage")!
        var usageReq = URLRequest(url: usageUrl)
        usageReq.setValue("sessionKey=" + sessionKey, forHTTPHeaderField: "Cookie")
        usageReq.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        
        let usage = await send(usageReq)
        let fetchedLimits = usage?.response.statusCode == 200 ? Self.parseUsageLimits(usage?.data) : nil
        
        if let backoff = retryAfter(usage?.response) {
            desktopRetryAfter = Date().addingTimeInterval(backoff)
        } else if fetchedLimits != nil {
            desktopRetryAfter = nextPacedRequest(after: requestStart)
        }
        
        // A transient usage failure shouldn't make a paid plan look like the free tier
        return ClaudeState(account: account, limits: rememberLimits(fetchedLimits), isConnected: true)
    }
    
    // MARK: - Fallback Claude CLI ~/.claude.json
    
    private func fetchFromClaudeJson() async -> ClaudeState? {
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
        
        return ClaudeState(account: account, limits: await fetchUsageWithOAuth(), isConnected: true)
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
        let fhRemaining = remaining(fhObj?["utilization"] as? Double) ?? 100
        let sdRemaining = remaining(sdObj?["utilization"] as? Double) ?? 100
        
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
            hasFiveHourWindow: fhObj != nil,
            hasWeeklyWindow: sdObj != nil,
            lastUpdated: Date()
        )
    }
    
    private var oauthRetryAfter = Date.distantPast
    private var desktopRetryAfter = Date.distantPast
    /// Account from the last successful claude.ai organizations request, reused while paced.
    private var lastDesktopAccount: ClaudeAccountInfo?
    private var lastGoodLimits: ClaudeUsageLimits?
    private var lastGoodAt = Date.distantPast
    /// Mirrors the user's refresh interval (seconds; 0 = manual, every fetch goes through).
    private var usagePollInterval: TimeInterval = 60
    private let rateLimitBackoff: TimeInterval = 60     // floor after a 429 (the endpoint sends Retry-After: 0)
    private var staleGrace: TimeInterval { max(900, usagePollInterval * 3) }  // keep last good numbers through brief failures
    
    /// Earliest time the next usage request may go out. Measured from when the request started and kept
    /// a little under the poll interval: timer ticks are spaced exactly one interval apart, so pacing a full
    /// interval from when the response arrived would skip every other tick.
    private func nextPacedRequest(after start: Date) -> Date {
        start.addingTimeInterval(usagePollInterval * 0.8)
    }
    
    /// Fetches usage with the Claude Code OAuth token. The token is only ever sent as a Bearer
    /// header to https://api.anthropic.com (HTTPS); it is never logged, stored, or sent elsewhere.
    /// The refresh token is never read or used: when the access token expires we simply fail
    /// and pick up the new token once Claude Code refreshes it in the Keychain.
    /// Requests follow the user's refresh interval; the last good result is reused for up to `staleGrace`, after which nil
    /// (the "Connection Lost" state) is returned.
    private func fetchUsageWithOAuth() async -> ClaudeUsageLimits? {
        var fresh: ClaudeUsageLimits?
        if Date() >= oauthRetryAfter {
            let requestStart = Date()
            fresh = await requestUsage()
            if fresh != nil {
                oauthRetryAfter = nextPacedRequest(after: requestStart)
            }
        }
        return rememberLimits(fresh)
    }
    
    /// Records a successful result, or falls back to the last good one while it's within `staleGrace`.
    private func rememberLimits(_ fresh: ClaudeUsageLimits?) -> ClaudeUsageLimits? {
        if let fresh = fresh {
            lastGoodLimits = fresh
            lastGoodAt = Date()
            return fresh
        }
        return Date().timeIntervalSince(lastGoodAt) <= staleGrace ? lastGoodLimits : nil
    }
    
    private func requestUsage() async -> ClaudeUsageLimits? {
        guard let token = ClaudeKeyChainHelper.getClaudeCodeOAuthToken() else { return nil }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        
        let usage = await send(req)
        if let backoff = retryAfter(usage?.response) {
            oauthRetryAfter = Date().addingTimeInterval(backoff)
        }
        guard usage?.response.statusCode == 200 else { return nil }
        return Self.parseUsageLimits(usage?.data)
    }
    
    public static func parseDate(_ val: Any?) -> Date? {
        guard let val = val else { return nil }
        if let str = val as? String, !str.isEmpty {
            return DateParsing.iso8601(str)
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
        
        // Chromium cookie DB v24+ prefixes each decrypted value with a 32-byte SHA-256 of the host
        let hasHostDigestPrefix = cookieDBVersion(db) >= 24
        
        var stmt: OpaquePointer?
        let query = "SELECT encrypted_value FROM cookies WHERE name = ? AND host_key LIKE '%claude.ai' ORDER BY length(host_key) DESC LIMIT 1"
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
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
            let prefixLength = hasHostDigestPrefix ? 32 : 0
            if status == kCCSuccess && numBytesDecrypted > prefixLength {
                let res = Data(decrypted.prefix(numBytesDecrypted))
                return String(data: res.subdata(in: prefixLength..<res.count), encoding: .utf8)
            }
        }
        return nil
    }
    
    private static func cookieDBVersion(_ db: OpaquePointer?) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM meta WHERE key = 'version'", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) else { return 0 }
        return Int(String(cString: text)) ?? 0
    }
    
    static func resetKeyCache() {
        cachedSafeStorageKey = nil
        hasAttemptedSafeStorageKey = false
    }
}
