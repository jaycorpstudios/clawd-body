import Foundation

/// Peripheral identifiers of paired buddies; the bond keys themselves stay in macOS.
public struct TrustedBuddies: Sendable {
    public let path: String

    public static var defaultPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Hilo/buddies.json").path(percentEncoded: false)
    }

    public init(path: String = TrustedBuddies.defaultPath) {
        self.path = path
    }

    public func load() -> [UUID] {
        guard let data = FileManager.default.contents(atPath: path),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return ids.compactMap(UUID.init(uuidString:))
    }

    public func add(_ id: UUID) throws {
        var ids = load()
        guard !ids.contains(id) else { return }
        ids.append(id)
        try save(ids)
    }

    public func remove(_ id: UUID) throws {
        try save(load().filter { $0 != id })
    }

    private func save(_ ids: [UUID]) throws {
        let url = URL(filePath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(ids.map(\.uuidString)).write(to: url, options: .atomic)
    }
}
