import AppKit
import Foundation
import HiloContract
import HiloCore

public protocol MediaPlayer: Sendable {
    func current() -> Media?
    func control(_ action: MediaAction)
}

/// Spotify and Music.app over AppleScript: only apps already running are asked (asking launches them), and only
/// playback commands exist. The first query triggers macOS's Automation prompt for each app.
public final class AppleScriptPlayer: MediaPlayer, @unchecked Sendable {
    struct App {
        let bundleId: String
        let durationDivisor: Double
    }

    public typealias Script = @Sendable (String) -> (output: String?, error: Int?)

    static let apps = [App(bundleId: "com.spotify.client", durationDivisor: 1000), App(bundleId: "com.apple.Music", durationDivisor: 1)]
    static let automationDenied = -1743
    /// Lets a permission granted later in System Settings take effect without restarting `hilod`.
    static let retryDeniedAfter = 300

    private let lock = NSLock()
    private var source: String?
    private var denied: [String: Int] = [:]
    private let isRunning: @Sendable (String) -> Bool
    private let script: Script
    private let now: @Sendable () -> Int
    private let log: @Sendable (String) -> Void

    public init(log: @escaping @Sendable (String) -> Void = { _ in },
                isRunning: @escaping @Sendable (String) -> Bool = AppleScriptPlayer.appIsRunning,
                script: @escaping Script = AppleScriptPlayer.runOnMain,
                now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) }) {
        self.log = log; self.isRunning = isRunning; self.script = script; self.now = now
    }

    public func current() -> Media? {
        var paused: (Media, String)?
        for app in Self.apps where isRunning(app.bundleId) {
            guard let media = query(app) else { continue }
            if media.playing != false {
                lock.withLock { source = app.bundleId }
                return media
            }
            if paused == nil { paused = (media, app.bundleId) }
        }
        lock.withLock { source = paused?.1 }
        return paused?.0
    }

    public func control(_ action: MediaAction) {
        guard let app = lock.withLock({ source }), isRunning(app) else { return }
        let command = switch action {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
        _ = run("tell application id \"\(app)\" to \(command)", app: app)
    }

    static func parse(_ line: String, durationDivisor: Double) -> Media? {
        let f = line.components(separatedBy: "\t")
        guard f.count == 5, !f[0].isEmpty, let duration = Double(f[2].replacingOccurrences(of: ",", with: ".")),
              let position = Double(f[3].replacingOccurrences(of: ",", with: ".")) else { return nil }
        let length = max(0, Int(duration / durationDivisor))
        return Media(title: Text.clip(f[0], 80), artist: Text.clip(f[1], 80), lengthS: length,
                     positionS: min(length, max(0, Int(position))), playing: f[4] == "playing")
    }

    private func query(_ app: App) -> Media? {
        let script = """
        tell application id "\(app.bundleId)"
          if player state is stopped then return ""
          set t to current track
          return (name of t) & tab & (artist of t) & tab & ((duration of t) as integer) & tab & ((player position) as integer) & tab & (player state as text)
        end tell
        """
        return run(script, app: app.bundleId).flatMap { Self.parse($0, durationDivisor: app.durationDivisor) }
    }

    private func run(_ source: String, app: String) -> String? {
        let t = now()
        let deniedAt = lock.withLock { denied[app] }
        if let deniedAt, t - deniedAt < Self.retryDeniedAfter { return nil }
        let (output, error) = script("with timeout of 5 seconds\n\(source)\nend timeout")
        if error == Self.automationDenied {
            lock.withLock { denied[app] = t }
            if deniedAt == nil {
                log("Automation for \(app) is denied; allow it in System Settings › Privacy & Security › Automation (hilod retries every \(Self.retryDeniedAfter / 60) min)")
            }
        } else if deniedAt != nil, error == nil {
            lock.withLock { _ = denied.removeValue(forKey: app) }
            log("Automation for \(app) is allowed now")
        }
        return output
    }

    public static let appIsRunning: @Sendable (String) -> Bool = {
        !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
    }

    public static let runOnMain: Script = { source in
        DispatchQueue.main.sync {
            var error: NSDictionary?
            let out = NSAppleScript(source: source)?.executeAndReturnError(&error)
            return (out?.stringValue, (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue)
        }
    }
}
