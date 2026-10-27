import Foundation

/// Masks likely secrets in text bound for the buddy. Errs on the side of masking: a hidden commit hash is cheap, a shown token is not.
public enum Redactor {
    public static let mask = "[redacted]"

    private static let name = #"[A-Za-z0-9_.-]*(?:token|secret|passw(?:or)?d|pwd|key|credential|auth|session|cookie)[A-Za-z0-9_.-]*"#
    private static let value = #"("[^"]*"|'[^']*'|[^\s"'&;|]+)"#

    private static let rules: [(NSRegularExpression, String)] = [
        (#"(?i)\b((?:proxy-)?authorization|(?:set-)?cookie|x-[a-z0-9-]*(?:key|token|auth|secret)[a-z0-9-]*)(\s*:\s*)[^"'\n]+"#, "$1$2\(mask)"),
        (#"(?i)\b([a-z][a-z0-9+.-]*://[^\s:/@"']+):[^\s@/"']+@"#, "$1:\(mask)@"),
        (#"(?i)(--?\#(name))(=|\s+)\#(value)"#, "$1$2\(mask)"),
        (#"(?i)(["']\#(name)["']\s*:\s*)("[^"]*"|'[^']*')"#, "$1\"\(mask)\""),
        (#"(?im)^(\s*\#(name)\s*:\s*)(?!\[redacted\])(\S.*)$"#, "$1\(mask)"),
        (#"(?i)\b(\#(name))(\s*=\s*)\#(value)"#, "$1$2\(mask)"),
        (#"\bAKIA[0-9A-Z]{16}\b"#, mask),
        (#"\b[0-9a-fA-F]{32,}\b"#, mask),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    private static let tokenRun = try! NSRegularExpression(pattern: #"[A-Za-z0-9+/=_-]{32,}"#)

    public static func redact(_ text: String) -> String {
        let structured = rules.reduce(text) { text, rule in
            rule.0.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: rule.1)
        }
        return maskRandomRuns(structured)
    }

    /// Long base64-like runs that switch character class often; paths and identifiers switch rarely.
    private static func maskRandomRuns(_ text: String) -> String {
        var result = text
        for match in tokenRun.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result), looksRandom(result[range]) else { continue }
            result.replaceSubrange(range, with: mask)
        }
        return result
    }

    static func looksRandom(_ run: Substring) -> Bool {
        func kind(_ c: Character) -> Int { c.isLowercase ? 0 : c.isUppercase ? 1 : c.isNumber ? 2 : 3 }
        let kinds = run.map(kind)
        guard Set(kinds).isSuperset(of: [0, 1, 2]) else { return false }
        let switches = zip(kinds, kinds.dropFirst()).filter { $0 != $1 }.count
        return Double(switches) >= 0.3 * Double(run.count)
    }
}
