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
}
