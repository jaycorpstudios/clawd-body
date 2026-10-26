import Foundation

/// Per-Mac settings shared by `hilod` and the Hilo app. Command-line flags still win in `hilod`.
public struct HiloConfig: Codable, Equatable, Sendable {
    public static let defaultHost = "work"

    public var host: String?
    public var tokensFromTranscripts: Bool?

    public init(host: String? = nil, tokensFromTranscripts: Bool? = nil) {
        self.host = host; self.tokensFromTranscripts = tokensFromTranscripts
    }

    enum CodingKeys: String, CodingKey { case host, tokensFromTranscripts = "tokens_from_transcripts" }

    public static var defaultPath: String {
        if let path = ProcessInfo.processInfo.environment["HILO_CONFIG"] { return path }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Hilo/config.json").path(percentEncoded: false)
    }

    public static func load(path: String = defaultPath) -> HiloConfig {
        guard let data = FileManager.default.contents(atPath: path),
              let config = try? JSONDecoder().decode(HiloConfig.self, from: data) else { return HiloConfig() }
        return config
    }

    public func save(path: String = defaultPath) throws {
        let url = URL(filePath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// Turns a display name ("Work", "Home Mac") into the contract's host (`^[a-z0-9-]{1,16}$`); nil when nothing is left.
    public static func hostName(from display: String) -> String? {
        var out = ""
        for scalar in display.lowercased().folding(options: .diacriticInsensitive, locale: nil).unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) { out.unicodeScalars.append(scalar) }
            else if !out.isEmpty, !out.hasSuffix("-") { out += "-" }
        }
        while out.hasSuffix("-") { out.removeLast() }
        out = String(out.prefix(16))
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? nil : out
    }
}
