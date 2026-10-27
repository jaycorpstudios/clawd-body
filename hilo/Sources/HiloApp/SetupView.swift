import SwiftUI
import HiloContract
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
            step(5, "Buddy settings", done: false, optional: true) { BuddySettingsCard() }
            step(6, "Picture for this Mac", done: model.daemonStatus?.face != nil, optional: true) { ProfileCard() }
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

/// Same controls as the buddy's top panel. Values come from the buddy's `device.settings`, so both stay in step.
struct BuddySettingsCard: View {
    @Environment(AppModel.self) private var model
    @State private var volume = 60.0
    @State private var brightness = 100.0
    @State private var editing = false

    var body: some View {
        let reported = model.daemonStatus?.settings
        VStack(alignment: .leading, spacing: 14) {
            Text(reported == nil ? "Connect the buddy to change its settings. They live on the buddy, so its own panel (swipe down from the top) shows the same values."
                 : "Changes apply on the buddy, which confirms them; swiping down on the buddy opens the same panel.")
                .foregroundStyle(Theme.secondary)
            Toggle(isOn: Binding(get: { reported?.sound == true }, set: { model.changeSettings(SettingsChange(sound: $0)) })) {
                Text("Sound")
            }
            .toggleStyle(.switch)
            slider("Volume", value: $volume, range: 0...100, unit: "") { model.changeSettings(SettingsChange(volume: $0)) }
                .opacity(reported?.sound == true ? 1 : 0.5)
            slider("Brightness", value: $brightness, range: 10...100, unit: "%") { model.changeSettings(SettingsChange(brightness: $0)) }
            timeZone(reported)
        }
        .disabled(reported == nil)
        .onAppear(perform: sync)
        .onChange(of: reported) { sync() }
    }

    @ViewBuilder private func timeZone(_ reported: DeviceSettings?) -> some View {
        let mac = TimeZoneOffsets.current()
        HStack(spacing: 12) {
            Text("Time zone").frame(width: 84, alignment: .leading)
            if let tz = reported?.tzOffsetMin {
                Picker("Time zone", selection: Binding(get: { tz }, set: { model.changeSettings(SettingsChange(tzOffsetMin: $0)) })) {
                    ForEach(TimeZoneOffsets.choices, id: \.self) { Text(TimeZoneOffsets.label($0)).tag($0) }
                }
                .labelsHidden().frame(width: 140)
                Button("Use this Mac's") { if let mac { model.changeSettings(SettingsChange(tzOffsetMin: mac)) } }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(mac == nil || mac == tz)
                Text("No daylight saving: change it by hand when the clocks change.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            } else {
                Text(reported == nil ? "—" : "Update the buddy's firmware to set its time zone here.")
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func sync() {
        guard !editing, let s = model.daemonStatus?.settings else { return }
        volume = Double(s.volume)
        brightness = Double(s.brightness)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String,
                        commit: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 84, alignment: .leading)
            Slider(value: value, in: range, step: 1) { active in
                editing = active
                if !active { commit(Int(value.wrappedValue)) }
            }
            Text("\(Int(value.wrappedValue))\(unit)").font(Theme.mono).monospacedDigit().frame(width: 48, alignment: .trailing)
        }
    }
}
