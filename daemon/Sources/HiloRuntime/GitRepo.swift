import Foundation

public enum GitRepo {
    /// Nearest ancestor of `cwd` that contains `.git`; no git process is spawned.
    public static func root(of cwd: String) -> String? {
        var url = URL(filePath: cwd).standardized
        while url.path(percentEncoded: false) != "/" {
            if FileManager.default.fileExists(atPath: url.appending(path: ".git").path(percentEncoded: false)) {
                return url.path(percentEncoded: false).replacing(/\/$/, with: "")
            }
            url.deleteLastPathComponent()
        }
        return nil
    }

    /// The Hilo project of a directory: its repo's directory name, as the hooks name it; nil outside a repo.
    public static func project(of cwd: String) -> String? {
        root(of: cwd).map { URL(filePath: $0).lastPathComponent }
    }
}
