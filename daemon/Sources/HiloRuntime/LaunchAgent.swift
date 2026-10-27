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

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    private func check(_ result: (status: Int32, error: String), _ command: [String]) throws {
        guard result.status == 0 else {
            throw Failure(description: "launchctl \(command[0]) failed: \(result.error.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    public static let run: Launchctl = { arguments in
        let process = Process()
        process.executableURL = URL(filePath: "/bin/launchctl")
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (-1, "\(error)")
        }
        return (process.terminationStatus, String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    /// The `hilod` inside an installed Hilo.app, or next to the calling executable.
    public static func bundledHilod(executable: String = CommandLine.arguments[0]) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sibling = URL(filePath: executable).resolvingSymlinksInPath().deletingLastPathComponent().appending(path: "hilod")
        let candidates = ["/Applications/Hilo.app/Contents/MacOS/hilod", home.appending(path: "Applications/Hilo.app/Contents/MacOS/hilod").path(percentEncoded: false),
                          sibling.path(percentEncoded: false)]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
