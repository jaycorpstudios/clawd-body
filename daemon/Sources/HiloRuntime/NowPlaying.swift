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

    static let apps = [App(bundleId: "com.spotify.client", durationDivisor: 1000), App(bundleId: "com.apple.Music", durationDivisor: 1)]

    private let lock = NSLock()
    private var source: String?
    private var denied: Set<String> = []
    private let log: @Sendable (String) -> Void

    public init(log: @escaping @Sendable (String) -> Void = { _ in }) { self.log = log }

    public func current() -> Media? {
        var paused: (Media, String)?
        for app in Self.apps where running(app.bundleId) {
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
        guard let app = lock.withLock({ source }), running(app) else { return }
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

    private func running(_ bundleId: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    private func run(_ source: String, app: String) -> String? {
        guard !lock.withLock({ denied.contains(app) }) else { return nil }
        let (result, code): (String?, Int?) = DispatchQueue.main.sync {
            var error: NSDictionary?
            let out = NSAppleScript(source: source)?.executeAndReturnError(&error)
            return (out?.stringValue, (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue)
        }
        if code == -1743 {
            lock.withLock { _ = denied.insert(app) }
            log("Automation for \(app) is denied; allow it in System Settings › Privacy & Security › Automation, then restart hilod")
        }
        return result
    }
}
