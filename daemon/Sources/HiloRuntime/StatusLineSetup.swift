import Foundation

/// Whether Claude Code's status line already goes through `hilo statusline`, and the prompt that makes it so.
/// Hilo only reads `settings.json`; the change is left to a Claude Code session the user watches.
public enum StatusLineSetup {
    public enum State: Equatable, Sendable {
        case wrapped, notWrapped(command: String), noStatusLine, unreadable
    }

    public static var settingsPath: String {
        let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude").path(percentEncoded: false)
        return URL(filePath: dir).appending(path: "settings.json").path(percentEncoded: false)
    }

    public static func detect(path: String = settingsPath) -> State {
        guard let data = FileManager.default.contents(atPath: path) else { return .noStatusLine }
        return detect(data)
    }

    public static func detect(_ settings: Data) -> State {
        guard let root = try? JSONSerialization.jsonObject(with: settings) as? [String: Any] else { return .unreadable }
        guard let line = root["statusLine"] as? [String: Any],
              let command = (line["command"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty
        else { return .noStatusLine }
        return isWrapped(command) ? .wrapped : .notWrapped(command: command)
    }

    static func isWrapped(_ command: String) -> Bool {
        command.range(of: #"^(?:(['"])(?:[^'"]*/)?hilo\1|(?:\S*/)?hilo)\s+statusline(\s|$)"#, options: .regularExpression) != nil
    }

    public static func prompt(hilo: String) -> String {
        let exe = quoted(hilo)
        return """
        Please route my Claude Code status line through Hilo, so the Hilo buddy can show my usage. Edit only ~/.claude/settings.json (or settings.json in $CLAUDE_CONFIG_DIR if that is set).

        1. Copy the file to settings.json.bak-hilo next to it before changing anything (if that name is taken, add a timestamp).
        2. Look at statusLine.command:
           - If it already runs `hilo statusline` (any path to hilo), change nothing and tell me it is already set up.
           - If there is a command, replace it with `\(exe) statusline -- <current command>`, keeping the current command exactly as it is. If it uses shell syntax (pipes, &&, ;, redirections, $(...)), wrap it as `\(exe) statusline -- sh -c '<current command>'`, escaping single quotes.
           - If there is no statusLine, add "statusLine": {"type": "command", "command": "\(exe) statusline"}.
           Keep every other setting, and the rest of statusLine (type, padding), as it is. Never wrap it twice.
        3. Show me the diff and wait for my OK before saving.
        4. Then tell me how to check it: after my next message in Claude Code the status line refreshes, the buddy's usage ring moves within a few seconds, and Hilo › Setup › Usage says the status line goes through hilo statusline.
        """
    }

    static func quoted(_ path: String) -> String {
        path.allSatisfy { $0.isLetter || $0.isNumber || "/._-+".contains($0) } ? path : "'\(path.replacingOccurrences(of: "'", with: #"'\''"#))'"
    }
}
