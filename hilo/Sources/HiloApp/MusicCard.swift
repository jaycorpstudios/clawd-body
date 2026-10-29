import AppKit
import SwiftUI
import HiloRuntime

extension AppModel {
    func setMusic(spotify: Bool? = nil, app: Bool? = nil) {
        var updated = HiloConfig.load()
        if let spotify { updated.musicSpotify = spotify }
        if let app { updated.musicApp = app }
        do { try updated.save() } catch { notify("Cannot save the setting: \(error)", .error) }
        config = HiloConfig.load()
        refreshMusic()
    }

    /// Asks macOS without prompting and tells `hilod` to reload the switches.
    func refreshMusic() {
        Task.detached {
            let here = [AppleScriptPlayer.spotify, AppleScriptPlayer.music].reduce(into: [String: AutomationAccess]()) {
                $0[$1] = AutomationAccess.check($1)
            }
            let reply = LocalSocket.request(path: LocalSocket.defaultPath, op: "music", body: Data(), timeoutSeconds: 2)
            let status = reply.flatMap { try? JSONDecoder().decode(DaemonStatus.self, from: $0) }
            await MainActor.run {
                self.musicHere = here
                self.musicStatus = status?.music
            }
        }
    }

    /// A read-only query that makes macOS show the Automation prompt for this app; never launches the player.
    func allowMusic(_ bundleId: String) {
        guard !Snapshots.requested, AppleScriptPlayer.appIsRunning(bundleId) else { return refreshMusic() }
        var error: NSDictionary?
        _ = NSAppleScript(source: "tell application id \"\(bundleId)\" to get player state")?.executeAndReturnError(&error)
        refreshMusic()
    }
}

/// Which players `hilod` follows, and whether macOS lets it.
struct MusicCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The buddy's Music view shows what plays here and sends play, pause and skip back. With both off, hilod asks neither app and the buddy hides the view.")
                .foregroundStyle(Theme.secondary)
            row("Spotify", AppleScriptPlayer.spotify, on: model.config.musicSpotify ?? true,
                daemon: model.musicStatus?.spotifyAccess) { model.setMusic(spotify: $0) }
            row("Music", AppleScriptPlayer.music, on: model.config.musicApp ?? true,
                daemon: model.musicStatus?.appAccess) { model.setMusic(app: $0) }
            Text("Each app asks once. hilod has its own permission; if it shows denied, allow it in System Settings › Privacy & Security › Automation.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .onAppear { model.refreshMusic() }
    }

    private func row(_ name: String, _ bundleId: String, on: Bool, daemon: AutomationAccess?,
                     set: @escaping (Bool) -> Void) -> some View {
        let here = model.musicHere[bundleId]
        return HStack(spacing: 12) {
            Toggle(isOn: Binding(get: { on }, set: set)) { Text(name) }
                .toggleStyle(.switch).frame(width: 130, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("Hilo: \(Self.describe(here))")
                Text("hilod: \(Self.describe(daemon))")
            }
            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            Spacer()
            Button("Allow control") { model.allowMusic(bundleId) }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!on || here == .allowed || here == .notRunning)
                .help(here == .notRunning ? "Open \(name) first; Hilo never launches it." : "Shows macOS's Automation prompt for \(name).")
        }
        .opacity(on ? 1 : 0.6)
    }

    static func describe(_ access: AutomationAccess?) -> String {
        switch access {
        case .allowed: "allowed"
        case .denied: "denied"
        case .notAsked: "not asked yet"
        case .notRunning: "app closed"
        case .unknown, nil: "—"
        }
    }
}
