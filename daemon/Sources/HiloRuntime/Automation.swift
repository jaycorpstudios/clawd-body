import CoreServices
import Foundation

/// macOS Automation consent for one app, read without ever showing the prompt. Each process has its own:
/// Hilo.app's answer says nothing about `hilod`'s.
public enum AutomationAccess: String, Codable, Sendable {
    case allowed, denied, notAsked = "not_asked", notRunning = "not_running", unknown

    public static func check(_ bundleId: String) -> AutomationAccess {
        var target = AEAddressDesc()
        let id = Array(bundleId.utf8)
        guard AECreateDesc(typeApplicationBundleID, id, id.count, &target) == noErr else { return .unknown }
        defer { AEDisposeDesc(&target) }
        return access(AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), false))
    }

    static func access(_ status: OSStatus) -> AutomationAccess {
        switch Int(status) {
        case Int(noErr): .allowed
        case errAEEventNotPermitted: .denied
        case errAEEventWouldRequireUserConsent: .notAsked
        case procNotFound: .notRunning
        default: .unknown
        }
    }
}

/// What `hilod` follows and whether macOS lets it; part of the `music` op's reply.
public struct MusicStatus: Codable, Equatable, Sendable {
    public var spotify: Bool
    public var app: Bool
    public var spotifyAccess: AutomationAccess
    public var appAccess: AutomationAccess

    public init(spotify: Bool, app: Bool, spotifyAccess: AutomationAccess, appAccess: AutomationAccess) {
        self.spotify = spotify; self.app = app; self.spotifyAccess = spotifyAccess; self.appAccess = appAccess
    }

    enum CodingKeys: String, CodingKey { case spotify, app, spotifyAccess = "spotify_access", appAccess = "app_access" }
}
