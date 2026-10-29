import Darwin
import Foundation

/// `hilod` as a per-user LaunchAgent, so macOS ties the Bluetooth permission to `hilod` itself and it starts at login.
public struct LaunchAgent: Sendable {
    public static let label = "dev.hilo.hilod"

    public let logPath: String
    public let plistPath: String
    public let domain: String

    public static var defaultLogPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Hilo/hilod.log").path(percentEncoded: false)
    }

    public static var defaultPlistPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/LaunchAgents/\(label).plist").path(percentEncoded: false)
    }

    public init(logPath: String = LaunchAgent.defaultLogPath, plistPath: String = LaunchAgent.defaultPlistPath,
                domain: String = "gui/\(getuid())") {
        self.logPath = logPath; self.plistPath = plistPath; self.domain = domain
    }

    public func plist(hilod: String) throws -> Data {
        let job: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [hilod],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath,
        ]
        return try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)
    }

    /// The first `remove` drops a job started with `launchctl submit`, which would otherwise hold the label.
    public var installCommands: [[String]] {
        [["remove", Self.label], ["bootout", "\(domain)/\(Self.label)"], ["bootstrap", domain, plistPath]]
    }

    public var uninstallCommands: [[String]] {
        [["bootout", "\(domain)/\(Self.label)"], ["remove", Self.label]]
    }

    public var restartCommand: [String] { ["kickstart", "-k", "\(domain)/\(Self.label)"] }

    public var isInstalled: Bool { FileManager.default.fileExists(atPath: plistPath) }

    public typealias Launchctl = @Sendable ([String]) -> (status: Int32, error: String)

    public func install(hilod: String, launchctl: Launchctl = LaunchAgent.run) throws {
        let fm = FileManager.default
        for dir in [plistPath, logPath].map({ URL(filePath: $0).deletingLastPathComponent() }) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try plist(hilod: hilod).write(to: URL(filePath: plistPath), options: .atomic)
        let commands = installCommands
        for command in commands.dropLast() { _ = launchctl(command) }
        let bootstrap = commands.last!
        var result = launchctl(bootstrap)
        // bootout returns before the old instance is gone; bootstrap fails with EIO until then.
        for _ in 0..<5 where result.status != 0 {
            usleep(400_000)
            result = launchctl(bootstrap)
        }
        try check(result, bootstrap)
    }

    /// Stops the job and removes the plist; succeeds when nothing was installed.
    public func uninstall(launchctl: Launchctl = LaunchAgent.run) throws {
        for command in uninstallCommands { _ = launchctl(command) }
        if isInstalled { try FileManager.default.removeItem(atPath: plistPath) }
    }

    public func restart(launchctl: Launchctl = LaunchAgent.run) throws {
        try check(launchctl(restartCommand), restartCommand)
    }

    /// Why launchd's job is not up, in words a user can act on; nil when `launchctl print` names no exit.
    public func whyNotRunning(print: String) -> String? {
        func field(_ name: String) -> String? {
            print.split(separator: "\n").lazy.compactMap { line -> String? in
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                return parts.count == 2 && parts[0] == name ? parts[1] : nil
            }.first
        }
        if field("last exit reason") == "OS_REASON_TCC" {
            return "macOS stopped hilod for lack of a privacy permission (Bluetooth). Rebuild Hilo with scripts/build-hilo-app.sh, start hilod again and allow Bluetooth when asked, or turn it on in System Settings › Privacy & Security › Bluetooth."
        }
        if let reason = field("last exit reason") { return "hilod stopped: \(reason). Log in ~/Library/Logs/Hilo." }
        if let code = field("last exit code"), code != "0", code != "(never exited)" {
            return "hilod exited with \(code). Log in ~/Library/Logs/Hilo."
        }
        return nil
    }

    public var printCommand: [String] { ["print", "\(domain)/\(Self.label)"] }

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    private func check(_ result: (status: Int32, error: String), _ command: [String]) throws {
        guard result.status == 0 else {
            throw Failure(description: "launchctl \(command[0]) failed: \(result.error.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    public static let run: Launchctl = { arguments in
        let result = launch(arguments)
        return (result.status, result.error)
    }

    /// `launchctl print`'s text for the job, empty when it cannot run.
    public func printed() -> String { Self.launch(printCommand).output }

    private static func launch(_ arguments: [String]) -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/launchctl")
        process.arguments = arguments
        let output = Pipe(), errors = Pipe()
        process.standardError = errors
        process.standardOutput = output
        do {
            try process.run()
        } catch {
            return (-1, "", "\(error)")
        }
        let out = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: out, as: UTF8.self),
                String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    /// The `hilod` inside an installed Hilo.app (`Contents/Helpers`), or next to the calling executable.
    public static func bundledHilod(executable: String = CommandLine.arguments[0]) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sibling = URL(filePath: executable).resolvingSymlinksInPath().deletingLastPathComponent().appending(path: "hilod")
        let helpers = URL(filePath: executable).resolvingSymlinksInPath().deletingLastPathComponent().appending(path: "../Helpers/hilod").standardized
        let candidates = ["/Applications/Hilo.app/Contents/Helpers/hilod", home.appending(path: "Applications/Hilo.app/Contents/Helpers/hilod").path(percentEncoded: false),
                          helpers.path(percentEncoded: false), sibling.path(percentEncoded: false)]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
