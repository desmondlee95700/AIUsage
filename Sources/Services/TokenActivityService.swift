import Foundation

/// Reads daily token activity from the session logs Claude Code and Codex keep on disk.
/// Purely local file reads: no network, no tokens consumed.
///
/// - Claude Code: `~/.claude/projects/<project>/<session>.jsonl`, one `usage` per assistant message
/// - Codex: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, `token_count` events per turn
///
/// Both logs cover coding sessions from the desktop apps as well as the CLIs (Claude Code
/// records `entrypoint` "claude-desktop" or "cli"; Codex records `originator`, e.g.
/// "Codex Desktop"). Regular chats in Claude, ChatGPT, claude.ai and chatgpt.com don't leave
/// token counts on disk, so they aren't included.
/// `@unchecked Sendable`: the only mutable state, `cache`, is confined to the serial `queue`.
public final class TokenActivityService: @unchecked Sendable {
    public static let shared = TokenActivityService()

    public static let dayCount = TokenActivityRange.longest.rawValue

    struct ParsedEntry {
        /// Dedupe key; nil when the source has no stable id
        let key: String?
        let timestamp: Date
        let usage: TokenUsage
    }

    private struct CachedFile {
        let modified: Date
        let size: Int
        let entries: [ParsedEntry]
    }

    private let queue = DispatchQueue(label: "AIUsage.TokenActivity", qos: .utility)
    /// Parsed results per file, reused until the file's size or mtime changes. Only touched on `queue`.
    private var cache: [String: CachedFile] = [:]

    private init() {}

    // MARK: - Public API

    public func loadClaude() async -> TokenActivitySummary? {
        await load(roots: Self.claudeProjectRoots, parser: { Self.parseClaudeLog($0) })
    }

    public func loadCodex() async -> TokenActivitySummary? {
        await load(roots: Self.codexSessionRoots, parser: { Self.parseCodexLog($0) })
    }

    // MARK: - Locations

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static var claudeProjectRoots: [URL] {
        var roots: [URL] = []
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            roots.append(URL(fileURLWithPath: custom).appendingPathComponent("projects"))
        }
        roots.append(home.appendingPathComponent(".claude/projects"))
        roots.append(home.appendingPathComponent(".config/claude/projects"))
        return roots
    }

    static var codexSessionRoots: [URL] {
        var roots: [URL] = []
        if let custom = ProcessInfo.processInfo.environment["CODEX_HOME"], !custom.isEmpty {
            roots.append(URL(fileURLWithPath: custom).appendingPathComponent("sessions"))
        }
        roots.append(home.appendingPathComponent(".codex/sessions"))
        return roots
    }

    // MARK: - Loading

    /// Scans on `queue`, which serializes access to `cache` and keeps the file reads off the caller's thread.
    private func load(roots: [URL], parser: @escaping @Sendable (Data) -> [ParsedEntry]) async -> TokenActivitySummary? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.scan(roots: roots, parser: parser))
            }
        }
    }

    /// Returns nil when none of the roots exist (tool never used on this Mac).
    private func scan(roots: [URL], parser: (Data) -> [ParsedEntry]) -> TokenActivitySummary? {
        let fm = FileManager.default
        let calendar = Calendar.current
        let now = Date()
        guard let windowStart = calendar.date(
            byAdding: .day, value: -(Self.dayCount - 1), to: calendar.startOfDay(for: now)
        ) else { return nil }

        var foundRoot = false
        var seenPaths = Set<String>()
        var seenKeys = Set<String>()
        var entries: [(timestamp: Date, usage: TokenUsage)] = []
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]

        for root in roots {
            guard fm.fileExists(atPath: root.path),
                  let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            else { continue }
            foundRoot = true

            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                let path = url.resolvingSymlinksInPath().path
                guard seenPaths.insert(path).inserted,
                      let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate,
                      // A file untouched since before the window can't hold entries inside it
                      modified >= windowStart
                else { continue }
                let size = values.fileSize ?? 0

                let parsed: [ParsedEntry]
                if let cached = cache[path], cached.modified == modified, cached.size == size {
                    parsed = cached.entries
                } else {
                    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
                    parsed = parser(data).filter { $0.timestamp >= windowStart }
                    cache[path] = CachedFile(modified: modified, size: size, entries: parsed)
                }

                for entry in parsed {
                    // Resumed or forked sessions copy earlier messages into a new file
                    if let key = entry.key, !seenKeys.insert(key).inserted { continue }
                    entries.append((entry.timestamp, entry.usage))
                }
            }
        }

        // Drop cache entries for files that aged out of the window or were deleted
        cache = cache.filter { seenPaths.contains($0.key) }

        guard foundRoot else { return nil }
        return TokenActivitySummary.build(from: entries, dayCount: Self.dayCount, now: now, calendar: calendar)
    }

    // MARK: - Parsing

    static func parseTimestamp(_ string: String) -> Date? {
        DateParsing.iso8601(string)
    }

    /// Splits JSONL into lines and decodes only those containing `marker`, skipping the
    /// bulk of each log (message text, tool output) without a JSON parse.
    private static func jsonObjects(in data: Data, containing marker: String) -> [[String: Any]] {
        let markerBytes = Data(marker.utf8)
        var objects: [[String: Any]] = []
        for line in data.split(separator: UInt8(ascii: "\n")) where line.range(of: markerBytes) != nil {
            if let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] {
                objects.append(object)
            }
        }
        return objects
    }

    private static func int(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    /// Claude Code writes one line per content block, repeating the message's usage on each,
    /// so entries are keyed by message id + request id.
    static func parseClaudeLog(_ data: Data) -> [ParsedEntry] {
        jsonObjects(in: data, containing: "\"usage\"").compactMap { object in
            guard let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let timestampString = object["timestamp"] as? String,
                  let timestamp = parseTimestamp(timestampString)
            else { return nil }

            let messageId = message["id"] as? String
            let requestId = object["requestId"] as? String
            let key = messageId.map { "\($0)|\(requestId ?? "")" }

            return ParsedEntry(
                key: key,
                timestamp: timestamp,
                usage: TokenUsage(
                    input: int(usage["input_tokens"]),
                    cacheRead: int(usage["cache_read_input_tokens"]),
                    cacheWrite: int(usage["cache_creation_input_tokens"]),
                    output: int(usage["output_tokens"])
                )
            )
        }
    }

    /// Codex emits `token_count` events carrying both the session's running total and the
    /// latest turn's usage. An event whose running total is unchanged repeats the previous
    /// turn, so it's skipped. Codex's `input_tokens` includes cached input.
    static func parseCodexLog(_ data: Data) -> [ParsedEntry] {
        var lastRunningTotal = 0
        return jsonObjects(in: data, containing: "\"token_count\"").compactMap { object in
            guard let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let last = info["last_token_usage"] as? [String: Any],
                  let timestampString = object["timestamp"] as? String,
                  let timestamp = parseTimestamp(timestampString)
            else { return nil }

            if let running = info["total_token_usage"] as? [String: Any] {
                let runningTotal = int(running["total_tokens"])
                guard runningTotal != lastRunningTotal else { return nil }
                lastRunningTotal = runningTotal
            }

            let input = int(last["input_tokens"])
            let cached = min(int(last["cached_input_tokens"]), input)
            return ParsedEntry(
                key: nil,
                timestamp: timestamp,
                usage: TokenUsage(
                    input: input - cached,
                    cacheRead: cached,
                    cacheWrite: int(last["cache_write_input_tokens"]),
                    output: int(last["output_tokens"])
                )
            )
        }
    }
}
