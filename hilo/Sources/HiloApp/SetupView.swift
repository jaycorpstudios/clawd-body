import SwiftUI
import HiloRuntime

struct SetupView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var nameLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up this Mac").font(Theme.title(30))
                Text("Name it, keep hilod running and pair the buddy. Nothing here needs the terminal.").foregroundStyle(Theme.secondary)
            }
            step(1, "Name this Mac", done: model.config.host != nil) { nameCard }
            step(2, "Run hilod", done: model.daemonRunning) { daemonCard }
            step(3, "Pair the buddy", done: model.daemonStatus?.buddy.link == .connected) { buddyCard }
            step(4, "Usage on the buddy", done: false, optional: true) { usageCard }
        }
        .onAppear {
            guard !nameLoaded else { return }
            nameLoaded = true
            name = (model.config.host ?? HiloConfig.defaultHost).capitalized
        }
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The buddy shows this name in its top bar and next to each session, so you can tell your Macs apart.")
                .foregroundStyle(Theme.secondary)
            HStack(spacing: 8) {
                ForEach(["Work", "Home"], id: \.self) { preset in
                    Button(preset) { name = preset }.buttonStyle(SecondaryButtonStyle())
                }
                TextField("Name", text: $name).textFieldStyle(.plain).padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Theme.softPanel, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.lineStrong)).frame(width: 220)
                Button("Save") { model.saveHost(name) }.buttonStyle(PrimaryButtonStyle())
                    .disabled(HiloConfig.hostName(from: name) == nil)
            }
            HStack(spacing: 0) {
                Text("Sent to the buddy as ")
                Text(HiloConfig.hostName(from: name) ?? "—").font(Theme.mono).foregroundStyle(Theme.text)
                if let saved = model.config.host { Text(" · saved: ").padding(.leading, 4); Text(saved).font(Theme.mono) }
            }
            .font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
        }
    }

    private var daemonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle().fill(model.daemonRunning ? Theme.doneCheck : Theme.muted).frame(width: 9, height: 9)
                Text(model.daemonRunning ? "hilod is running as \(model.daemonStatus?.host ?? "?")" : "hilod is stopped")
                Spacer()
                if model.daemonRunning {
                    Button("Restart") { model.restartDaemon() }.buttonStyle(SecondaryButtonStyle())
                    Button("Stop") { model.stopDaemon() }.buttonStyle(SecondaryButtonStyle())
                } else {
                    Button("Start hilod") { model.startDaemon() }.buttonStyle(PrimaryButtonStyle())
                        .disabled(model.hilodPath == nil)
                }
            }
            Text(model.hilodPath.map { "Start installs the LaunchAgent \(LaunchAgent.label) for \($0): it runs now and at every login. Stop removes it. Log in ~/Library/Logs/Hilo." }
                 ?? "hilod was not found next to Hilo. Build it with scripts/build-hilod.sh, then rebuild the app.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
            if let error = model.daemonError {
                Text(error).font(.system(size: 12.5)).foregroundStyle(Color(hex: "#ff9a9d"))
            }
        }
    }

    private var buddyCard: some View {
        let buddy = model.daemonStatus?.buddy ?? BuddyStatus(link: .disconnected)
        let guide = PairingGuide.describe(buddy)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                PetView(state: buddy.link == .connected ? .happy : guide.active ? .working : .sleep, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.daemonRunning ? guide.title : "Start hilod first").font(.system(size: 14, weight: .semibold))
                    Text(model.daemonRunning ? guide.detail : "Pairing runs inside hilod.").foregroundStyle(Theme.secondary)
                }
                Spacer()
                if guide.active {
                    if buddy.pairing == .scanning || buddy.pairing == .connecting { ProgressView().controlSize(.small) }
                    Button("Cancel") { model.cancelPairing() }.buttonStyle(SecondaryButtonStyle())
                } else if model.daemonRunning && buddy.link != .connected {
                    Button(buddy.pairing == .idle ? "Start pairing" : "Retry") { model.startPairing() }.buttonStyle(PrimaryButtonStyle())
                        .disabled(buddy.link == .bluetoothOff || buddy.link == .unauthorized)
                }
            }
            if buddy.link != .connected {
                VStack(alignment: .leading, spacing: 6) {
                    instruction(1, "On the buddy's Home view, hold the side button for 5 seconds until the pairing screen appears.")
                    instruction(2, "Click Start pairing. hilod looks for the buddy for up to a minute.")
                    instruction(3, "macOS shows a pairing dialog: type the 6-digit code the buddy displays.")
                }
            }
        }
    }

    private var usageCard: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 12) {
            Text("The 5 h and weekly percentages come from Claude Code's status line. Set this as the status line command in ~/.claude/settings.json (keep your own command after the --):")
                .foregroundStyle(Theme.secondary)
            HStack {
                Text(AppModel.statusLineCommand).font(Theme.mono).textSelection(.enabled)
                Spacer()
                Button("Copy") { model.copy(AppModel.statusLineCommand) }.buttonStyle(SecondaryButtonStyle())
            }
            .padding(10).background(Theme.softPanel, in: RoundedRectangle(cornerRadius: 8))
            Toggle(isOn: Binding(get: { model.config.tokensFromTranscripts == true }, set: { model.setTokensFromTranscripts($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Count today's tokens from Claude Code's local transcripts")
                    Text("Reads ~/.claude/projects on this Mac. Applies when hilod restarts.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    private func step<Content: View>(_ n: Int, _ title: String, done: Bool, optional: Bool = false,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(done ? Theme.selected : Theme.softPanel).frame(width: 26, height: 26)
                    if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.selectedText) }
                    else { Text("\(n)").font(.system(size: 12.5, weight: .bold)).foregroundStyle(Theme.secondary) }
                }
                Text(title).font(.system(size: 16, weight: .semibold))
                if optional { Text("optional").font(.system(size: 11.5)).foregroundStyle(Theme.muted) }
            }
            content()
        }
        .padding(18).frame(maxWidth: 760, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }

    private func instruction(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n).").monospacedDigit().foregroundStyle(Theme.muted)
            Text(text).foregroundStyle(Theme.secondary)
        }
        .font(.system(size: 12.5))
    }
}
