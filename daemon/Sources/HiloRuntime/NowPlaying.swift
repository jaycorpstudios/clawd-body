import AppKit
import Foundation
import HiloContract
import HiloCore

public protocol MediaPlayer: Sendable {
    func current() -> Media?
    func control(_ action: MediaAction)
    /// Encoded image bytes of the current track's cover; may block, so callers run it off the coordinator.
    func artwork() -> Data?
    func follow(spotify: Bool, music: Bool)
}

extension MediaPlayer {
    public func artwork() -> Data? { nil }
    public func follow(spotify: Bool, music: Bool) {}
}

/// Spotify and Music.app over AppleScript: only apps already running are asked (asking launches them), and only
/// playback commands exist. The first query triggers macOS's Automation prompt for each app.
public final class AppleScriptPlayer: MediaPlayer, @unchecked Sendable {
    struct App {
        let bundleId: String
        let durationDivisor: Double
    }

    public typealias Script = @Sendable (String) -> (output: String?, error: Int?)
    public typealias DataScript = @Sendable (String) -> (output: Data?, error: Int?)
    public typealias Download = @Sendable (URL) -> Data?

    public static let spotify = "com.spotify.client", music = "com.apple.Music"
    static let apps = [App(bundleId: spotify, durationDivisor: 1000), App(bundleId: music, durationDivisor: 1)]
    static let automationDenied = -1743
    /// Lets a permission granted later in System Settings take effect without restarting `hilod`.
    static let retryDeniedAfter = 300

    private let lock = NSLock()
    private var source: String?
    private var denied: [String: Int] = [:]
    private var followed: Set<String> = [spotify, music]
    private let isRunning: @Sendable (String) -> Bool
    private let script: Script
    private let dataScript: DataScript
    private let download: Download
    private let now: @Sendable () -> Int
    private let log: @Sendable (String) -> Void

    public init(log: @escaping @Sendable (String) -> Void = { _ in },
                isRunning: @escaping @Sendable (String) -> Bool = AppleScriptPlayer.appIsRunning,
                script: @escaping Script = AppleScriptPlayer.runOnMain,
                dataScript: @escaping DataScript = AppleScriptPlayer.runOnMainForData,
                download: @escaping Download = ArtworkDownload.fetch,
                now: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) }) {
        self.log = log; self.isRunning = isRunning; self.script = script; self.dataScript = dataScript
        self.download = download; self.now = now
    }

    public func current() -> Media? {
        var paused: (Media, String)?
        let followed = lock.withLock { self.followed }
        for app in Self.apps where followed.contains(app.bundleId) && isRunning(app.bundleId) {
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

    public func artwork() -> Data? {
        guard let app = lock.withLock({ source }), isRunning(app) else { return nil }
        if app == Self.spotify {
            return run("tell application id \"\(app)\" to return artwork url of current track", app: app)
                .flatMap(ArtworkDownload.allowedURL).flatMap(download)
        }
        return run("tell application id \"\(app)\" to return raw data of artwork 1 of current track", app: app, with: dataScript)
    }

    public func follow(spotify: Bool, music: Bool) {
        lock.withLock {
            followed = Set([spotify ? Self.spotify : nil, music ? Self.music : nil].compactMap { $0 })
            if let s = source, !followed.contains(s) { source = nil }
        }
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
        run(source, app: app, with: script)
    }

    private func run<T>(_ source: String, app: String, with script: (String) -> (output: T?, error: Int?)) -> T? {
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

    public static let runOnMainForData: DataScript = { source in
        DispatchQueue.main.sync {
            var error: NSDictionary?
            let out = NSAppleScript(source: source)?.executeAndReturnError(&error)
            return (out?.data, (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue)
        }
    }
}

/// Spotify only hands out a cover URL; it is fetched from Spotify's image CDN alone, anonymously, with a short
/// timeout and a size cap.
public enum ArtworkDownload {
    static let host = "i.scdn.co"
    static let maxBytes = 2 << 20
    static let timeout: TimeInterval = 5

    static func allowedURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), isAllowed(url) else { return nil }
        return url
    }

    static func isAllowed(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == host && url.user == nil && url.password == nil && (url.port ?? 443) == 443
    }

    public static let fetch: AppleScriptPlayer.Download = { url in
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: SameHostRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let done = DispatchSemaphore(value: 0)
        let result = Box()
        let task = session.dataTask(with: url) { data, response, _ in
            if let data, data.count <= maxBytes, (response as? HTTPURLResponse)?.statusCode == 200 { result.data = data }
            done.signal()
        }
        task.resume()
        guard done.wait(timeout: .now() + timeout + 1) == .success else {
            task.cancel()
            return nil
        }
        return result.data
    }

    private final class Box: @unchecked Sendable { var data: Data? }

    private final class SameHostRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            request.url.map(isAllowed) == true ? request : nil
        }
    }
}
