import Foundation

/// How the terminal prompt for a tool call ended, read from the end of the session transcript (a format internal to Claude Code).
public enum TranscriptTail {
    static let tailBytes: UInt64 = 256 * 1024

    /// Whether the latest `tool` call was rejected at the prompt. An approval writes nothing until the tool ends, so no result reads as approved.
    public static func rejected(path: String, tool: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > tailBytes ? size - tailBytes : 0)
        guard let data = try? handle.readToEnd() else { return false }
        return rejected(lines: data.split(separator: UInt8(ascii: "\n")), tool: tool)
    }

    static func rejected(lines: [Data.SubSequence], tool: String) -> Bool {
        var results: [String: Bool] = [:]
        for line in lines.reversed() {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let content = (json["message"] as? [String: Any])?["content"] as? [[String: Any]] else { continue }
            for item in content {
                switch item["type"] as? String {
                case "tool_result":
                    guard let id = item["tool_use_id"] as? String else { continue }
                    results[id] = json["toolUseResult"] as? String == "User rejected tool use"
                        || (item["content"] as? String)?.hasPrefix("The user doesn't want to proceed") == true
                case "tool_use" where item["name"] as? String == tool:
                    guard let id = item["id"] as? String else { continue }
                    return results[id] ?? false
                default: continue
                }
            }
        }
        return false
    }
}
