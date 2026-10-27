import Foundation

/// Sums today's API tokens from Claude Code's local transcripts (input + cache writes + output; cache reads left out).
/// The transcript format is internal to Claude Code, so this is opt-in.
public final class TranscriptTokens: @unchecked Sendable {
    private struct Line: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                var input_tokens: Int?
                var output_tokens: Int?
                var cache_creation_input_tokens: Int?
            }
            var id: String?
            var usage: Usage?
        }
        var type: String?
        var timestamp: String?
        var message: Message?
    }

    private let root: URL
    private var day: Date?
    private var offsets: [String: UInt64] = [:]
    private var seen: Set<String> = []
    private var total = 0
    private var perSession: [String: Int] = [:]
    private var changed: Set<String> = []
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static var defaultRoot: URL {
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            return URL(filePath: dir).appending(path: "projects")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects")
    }

    public init(root: URL = TranscriptTokens.defaultRoot) { self.root = root }

    public func scan(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        if day != today {
            day = today
            offsets = [:]
            seen = []
            total = 0
            perSession = [:]
        }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return total }
        for case let url as URL in files where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let modified = values.contentModificationDate, modified >= today else { continue }
            read(url, since: today)
        }
        return total
    }

    /// Whole-file totals of the sessions whose transcripts grew since the last call.
    public func takeSessionTotals() -> [String: Int] {
        defer { changed = [] }
        return perSession.filter { changed.contains($0.key) }
    }

    /// Transcripts are named after their session; a subagent's file sits below its session's directory.
    static func session(of url: URL) -> String {
        let names = [url.deletingPathExtension().lastPathComponent] + url.deletingLastPathComponent().pathComponents.reversed()
        return names.first { UUID(uuidString: $0) != nil } ?? names[0]
    }

    private func read(_ url: URL, since start: Date) {
        let path = url.path(percentEncoded: false)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let offset = offsets[path] ?? 0
        guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd(), !data.isEmpty,
              let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return }
        offsets[path] = offset + UInt64(lastNewline - data.startIndex + 1)
        let session = Self.session(of: url)
        let marker = Data(#""usage""#.utf8)
        for raw in data[data.startIndex...lastNewline].split(separator: UInt8(ascii: "\n")) where raw.range(of: marker) != nil {
            guard let line = try? JSONDecoder().decode(Line.self, from: raw), line.type == "assistant",
                  let id = line.message?.id, let usage = line.message?.usage,
                  seen.insert(id).inserted else { continue }
            let tokens = (usage.input_tokens ?? 0) + (usage.output_tokens ?? 0) + (usage.cache_creation_input_tokens ?? 0)
            perSession[session, default: 0] += tokens
            changed.insert(session)
            if let stamp = line.timestamp.flatMap(iso.date(from:)), stamp >= start { total += tokens }
        }
    }
}
