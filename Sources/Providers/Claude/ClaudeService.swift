import Foundation
import CommonCrypto
import SQLite3
import Security
import LocalAuthentication
import os

/// An actor, so the pacing and last-good state below is only touched by one fetch at a time.
/// QuotaService never overlaps refreshes, so fetches don't interleave across their awaits in practice.
public actor ClaudeService {
    public static let shared = ClaudeService()
    
    private let session: URLSession
    
    /// Claiming a reset is slower than a usage read; Claude Code allows it 25 seconds.
    private let resetSession: URLSession
    
    static let browserUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    
    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 6.0
        self.session = URLSession(configuration: config)
        
        let resetConfig = URLSessionConfiguration.ephemeral
        resetConfig.timeoutIntervalForRequest = 25.0
        resetConfig.timeoutIntervalForResource = 30.0
        self.resetSession = URLSession(configuration: resetConfig)
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
        // Keychain and cookie database reads block (the Keychain may even prompt), so keep them
        // off the cooperative pool
        let cookies = await runBlocking { () -> (sessionKey: String, lastActiveOrg: String?)? in
            guard let key = ClaudeKeyChainHelper.getSafeStorageKey(),
                  let sessionKey = ClaudeKeyChainHelper.getCookie(name: "sessionKey", key: key) else {
                return nil
            }
            return (sessionKey, ClaudeKeyChainHelper.getCookie(name: "lastActiveOrg", key: key))
        }
        guard let (sessionKey, lastOrgFromCookie) = cookies else {
            return nil
        }
        
        // Within the pacing window, reuse the last account and limits instead of hitting claude.ai again
        if Date() < desktopRetryAfter, let account = lastDesktopAccount {
            return ClaudeState(account: account, limits: rememberLimits(nil), isConnected: true)
        }
        let requestStart = Date()
        
        // 1. Fetch organization profile
        let orgsUrl = URL(string: "https://claude.ai/api/organizations")!
        var orgsReq = URLRequest(url: orgsUrl)
        orgsReq.setValue("sessionKey=" + sessionKey, forHTTPHeaderField: "Cookie")
        orgsReq.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        
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
        
        let usageUrl = URL(string: "https://claude.ai/api/organizations/\(orgUuid)/usage" + Self.usageQuery)!
        var usageReq = URLRequest(url: usageUrl)
        usageReq.setValue("sessionKey=" + sessionKey, forHTTPHeaderField: "Cookie")
        usageReq.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        
        let usage = await send(usageReq)
        let fetchedLimits = usage?.response.statusCode == 200 ? Self.parseUsageLimits(usage?.data) : nil
        
        if let backoff = retryAfter(usage?.response) {
            desktopRetryAfter = Date().addingTimeInterval(backoff)
        } else if fetchedLimits != nil {
            desktopRetryAfter = nextPacedRequest(after: requestStart)
            resetSource = .desktop(organization: orgUuid)
        }
        
        // A transient usage failure shouldn't make a paid plan look like the free tier
        return ClaudeState(account: account, limits: rememberLimits(fetchedLimits), isConnected: true)
    }
    
    // MARK: - Redeem a Limit Reset

    enum ResetSource: Equatable {
        /// claude.ai with the desktop session cookie
        case desktop(organization: String)
        /// api.anthropic.com with the Claude Code OAuth token
        case oauth(organization: String)
    }

    public enum ResetOutcome: Equatable, Sendable {
        case reset(resetsLeft: Int?)
        case alreadyUsed
        case notLimited
        case cooldown(until: Date?)
        case ineligible
        case unavailable

        public var isSuccess: Bool {
            if case .reset = self { return true }
            return false
        }

        public var userMessage: String {
            switch self {
            case .reset:
                return "Reset applied. Your limits have been refilled."
            case .alreadyUsed:
                return "This reset has already been used."
            case .notLimited:
                return "Nothing to reset yet: this reset works once you've hit a limit."
            case .cooldown(let until):
                let wait = until.flatMap { DateParsing.countdown(until: $0) }.map { " Try again in \($0)." } ?? " Try again later."
                return "Resets are cooling down after a recent one." + wait
            case .ineligible:
                return "This account can't use limit resets right now."
            case .unavailable:
                return "This reset isn't available right now."
            }
        }
    }

    /// Parses the reset endpoint's reply; unknown results read as unavailable, as Claude Code treats them.
    static func parseResetOutcome(_ data: Data) -> ResetOutcome? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        switch json["result"] as? String {
        case "reset": return .reset(resetsLeft: json["resets_left"] as? Int)
        case "already_used": return .alreadyUsed
        case "not_limited": return .notLimited
        case "cooldown": return .cooldown(until: parseDate(json["cooldown_until"]))
        case "ineligible": return .ineligible
        default: return .unavailable
        }
    }

    /// Body Claude Code sends to claim a reset. `request_id` lets the server recognise a repeated claim.
    static func resetRequestBody(grantId: String, requestId: String) -> Data? {
        try? JSONSerialization.data(withJSONObject: [
            "program": "cedar_ember",
            "grant_id": grantId,
            "request_id": requestId
        ])
    }

    /// Spends one free limit reset, sent to whichever source last returned usage. The only write
    /// request AIUsage makes to Claude, and only ever from the user's confirmed tap (AGENTS.md §6.3).
    public func redeemReset(grantId: String) async throws -> ResetOutcome {
        guard Self.isValidGrantId(grantId) else { throw Self.resetError("This reset couldn't be read. Refresh and try again.") }
        guard let source = resetSource else { throw Self.resetError("Claude isn't connected. Refresh and try again.") }

        let organization: String
        var request: URLRequest
        switch source {
        case .desktop(let org), .oauth(let org):
            organization = org
        }
        guard UUID(uuidString: organization) != nil else { throw Self.resetError("Claude organization not found. Refresh and try again.") }

        switch source {
        case .desktop:
            let sessionKey = await runBlocking { () -> String? in
                guard let key = ClaudeKeyChainHelper.getSafeStorageKey() else { return nil }
                return ClaudeKeyChainHelper.getCookie(name: "sessionKey", key: key)
            }
            guard let sessionKey = sessionKey else { throw Self.resetError("Claude's sign-in wasn't found. Open Claude and try again.") }
            request = URLRequest(url: URL(string: "https://claude.ai/api/organizations/\(organization)/reset_rate_limits")!)
            request.setValue("sessionKey=" + sessionKey, forHTTPHeaderField: "Cookie")
            request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        case .oauth:
            guard let token = await runBlocking({ ClaudeKeyChainHelper.getClaudeCodeOAuthToken() }) else {
                throw Self.resetError("Claude Code's sign-in has expired. Open Claude Code and try again.")
            }
            request = URLRequest(url: URL(string: "https://api.anthropic.com/api/organizations/\(organization)/reset_rate_limits")!)
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.resetRequestBody(grantId: grantId, requestId: UUID().uuidString.lowercased())

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await resetSession.data(for: request)
        } catch {
            throw Self.resetError("Couldn't reach Claude. Check whether the reset applied before trying again.")
        }
        guard let http = response as? HTTPURLResponse else { throw Self.resetError("Claude sent an unexpected reply.") }
        switch http.statusCode {
        case 200:
            guard let outcome = Self.parseResetOutcome(data) else { throw Self.resetError("Claude sent an unexpected reply.") }
            if outcome.isSuccess {
                // Let the refresh that follows read the new limits instead of the paced cache
                desktopRetryAfter = .distantPast
                oauthRetryAfter = .distantPast
            }
            return outcome
        case 401, 403:
            if case .oauth = source { ClaudeKeyChainHelper.invalidateClaudeCodeToken() }
            throw Self.resetError("Claude rejected the sign-in. Open Claude and try again.")
        case 429:
            throw Self.resetError("Claude is limiting requests. Try again in a minute.")
        default:
            throw Self.resetError("The reset request failed (HTTP \(http.statusCode)).")
        }
    }

    private static func resetError(_ message: String) -> NSError {
        NSError(domain: "ClaudeService", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
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
        
        lastOAuthOrganization = organizationUuid
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
        
        guard fhObj != nil || sdObj != nil || snObj != nil || soObj != nil else { return nil } // Free tier returns null limits
        
        func remaining(_ util: Double?) -> Int? {
            util.map { max(0, min(100, 100 - Int(round($0)))) }
        }
        let fhRemaining = remaining(fhObj?["utilization"] as? Double) ?? 100
        let sdRemaining = remaining(sdObj?["utilization"] as? Double) ?? 100
        // Extra usage is reported with `is_enabled: false` and null figures when it's turned off
        let extraEnabled = (extraObj?["is_enabled"] as? Bool) ?? true
        
        return ClaudeUsageLimits(
            fiveHourRemainingPercent: fhRemaining,
            fiveHourUsedPercent: 100 - fhRemaining,
            fiveHourResetTime: parseDate(fhObj?["resets_at"]),
            weeklyRemainingPercent: sdRemaining,
            weeklyUsedPercent: 100 - sdRemaining,
            weeklyResetTime: parseDate(sdObj?["resets_at"]),
            sonnetRemainingPercent: remaining(snObj?["utilization"] as? Double),
            sonnetResetTime: parseDate(snObj?["resets_at"]),
            opusRemainingPercent: remaining(soObj?["utilization"] as? Double),
            opusResetTime: parseDate(soObj?["resets_at"]),
            extraUsagePercent: extraEnabled ? remaining(extraObj?["utilization"] as? Double) : nil,
            hasFiveHourWindow: fhObj != nil,
            hasWeeklyWindow: sdObj != nil,
            resetGrants: parseResetGrants(usage["cedar_ember"]),
            scopedModelName: parseScopedModelName(usage["limits"]),
            lastUpdated: Date()
        )
    }

    /// Query that adds the `cedar_ember` block (free limit resets) to a usage response, as Claude Code requests it.
    static let usageQuery = "?cedar_ember=1"

    /// Grant ids the reset endpoint accepts (the same check Claude Code applies before claiming).
    static func isValidGrantId(_ id: String) -> Bool {
        id.range(of: "^[a-z0-9_-]{1,40}$", options: .regularExpression) != nil
    }

    /// Reset grants from the `cedar_ember` block; empty when the account isn't eligible or the block is missing.
    static func parseResetGrants(_ block: Any?) -> [ClaudeResetGrant] {
        guard let block = block as? [String: Any],
              (block["eligible"] as? Bool) == true,
              let grants = block["grants"] as? [[String: Any]] else { return [] }
        return grants.compactMap { grant in
            guard let id = grant["id"] as? String, isValidGrantId(id),
                  let resetsLeft = grant["resets_left"] as? Int else { return nil }
            return ClaudeResetGrant(
                id: id,
                label: grant["label"] as? String ?? "",
                resetsLeft: resetsLeft,
                expiresAt: parseDate(grant["ends_at"]),
                clears: grant["clears"] as? [String] ?? [],
                givesBackWeekly: grant["gives_back_weekly"] as? Bool ?? false,
                usableNow: (grant["usable_now"] as? Bool ?? false) && !(grant["paused"] as? Bool ?? false),
                unavailableReason: grant["unavailable_reason"] as? String
            )
        }
    }

    /// Display name of the model with its own weekly allowance (the `weekly_scoped` entry in `limits`).
    static func parseScopedModelName(_ limits: Any?) -> String? {
        guard let limits = limits as? [[String: Any]],
              let scoped = limits.first(where: { $0["kind"] as? String == "weekly_scoped" }),
              let model = (scoped["scope"] as? [String: Any])?["model"] as? [String: Any],
              let name = model["display_name"] as? String, !name.isEmpty else { return nil }
        return name
    }
    
    private var oauthRetryAfter = Date.distantPast
    /// Organization from ~/.claude.json, used to redeem resets through the OAuth source.
    private var lastOAuthOrganization: String?
    /// Source of the last successful usage read, which is also where a reset is redeemed.
    private var resetSource: ResetSource?
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
                resetSource = lastOAuthOrganization.map { .oauth(organization: $0) }
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
        // Runs /usr/bin/security, so keep it off the cooperative pool
        guard let token = await runBlocking({ ClaudeKeyChainHelper.getClaudeCodeOAuthToken() }) else { return nil }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage" + Self.usageQuery)!)
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        
        let usage = await send(req)
        if let backoff = retryAfter(usage?.response) {
            oauthRetryAfter = Date().addingTimeInterval(backoff)
        }
        if usage?.response.statusCode == 401 {
            ClaudeKeyChainHelper.invalidateClaudeCodeToken()
        }
        guard usage?.response.statusCode == 200 else { return nil }
        return Self.parseUsageLimits(usage?.data)
    }

    /// Claude Code's OAuth access token and when it expires.
    struct ClaudeCodeToken: Equatable, Sendable {
        let value: String
        let expiresAt: Date?

        func isExpired(at now: Date = Date()) -> Bool {
            expiresAt.map { $0 <= now } ?? false
        }
    }

    /// Parses the JSON Claude Code stores in its "Claude Code-credentials" Keychain item.
    static func parseClaudeCodeCredentials(_ data: Data) -> ClaudeCodeToken? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        let expiresAt = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return ClaudeCodeToken(value: token, expiresAt: expiresAt)
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

private enum ClaudeKeyChainHelper {
    private struct Cache {
        var safeStorageKey: [UInt8]?
        var hasAttemptedSafeStorageKey = false
        var claudeCodeToken: ClaudeService.ClaudeCodeToken?
    }

    /// Read on background threads (through runBlocking), so guarded by a lock
    private static let cache = OSAllocatedUnfairLock(initialState: Cache())

    static func getSafeStorageKey() -> [UInt8]? {
        if let cached = cache.withLock({ $0.hasAttemptedSafeStorageKey ? .some($0.safeStorageKey) : nil }) {
            return cached
        }
        let key = readSafeStorageKey()
        cache.withLock {
            $0.safeStorageKey = key
            $0.hasAttemptedSafeStorageKey = true
        }
        return key
    }

    private static func readSafeStorageKey() -> [UInt8]? {
        
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
        return cryptStatus == kCCSuccess ? derivedKey : nil
    }
    
    /// Reads the Claude Code OAuth access token (local only), cached in memory until it expires.
    static func getClaudeCodeOAuthToken() -> String? {
        if let cached = cache.withLock({ $0.claudeCodeToken }), !cached.isExpired() {
            return cached.value
        }
        let token = readClaudeCodeCredentials()
            .flatMap(ClaudeService.parseClaudeCodeCredentials)
            .flatMap { $0.isExpired() ? nil : $0 }
        cache.withLock { $0.claudeCodeToken = token }
        return token?.value
    }

    /// Drops the cached token, e.g. after a 401 when Claude Code has already rotated it.
    static func invalidateClaudeCodeToken() {
        cache.withLock { $0.claudeCodeToken = nil }
    }

    /// Reads the "Claude Code-credentials" item through /usr/bin/security instead of SecItemCopyMatching.
    /// Claude Code writes the item with that tool, so its ACL already trusts it and macOS doesn't prompt.
    /// A direct read asks for the login password on every AIUsage build (the ad-hoc signature changes,
    /// so "Always Allow" doesn't stick) and again whenever Claude Code rewrites the item.
    private static func readClaudeCodeCredentials() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? data : nil
        } catch {
            return nil
        }
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
        cache.withLock { $0 = Cache() }
    }
}
