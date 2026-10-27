import AppKit
import SwiftUI
import HiloStore

@main
struct HiloApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Hilo", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1080, minHeight: 700)
                .preferredColorScheme(.dark)
                .task { await Snapshots.runIfRequested(model) }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .sidebar) {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { i, section in
                    Button(section.rawValue) { model.section = section }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                }
            }
        }
    }
}

/// A SwiftPM executable starts as a background process; make it a regular app with a Dock icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            HStack(spacing: 0) {
                Sidebar().frame(width: 240)
                Rectangle().fill(Theme.line).frame(width: 1)
                ScrollView {
                    content.padding(28).frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Theme.window)
            }
        }
        .background(Theme.window)
        .ignoresSafeArea(.container, edges: .top)
        .foregroundStyle(Theme.text)
        .font(.system(size: 13.5))
    }

    @ViewBuilder private var content: some View {
        if let error = model.errorMessage {
            Text(error).foregroundStyle(Color(hex: "#ff9a9d")).padding(.bottom, 12)
        }
        switch model.section {
        case .today: TodayView()
        case .focus: FocusView()
        case .sessions: SessionsView()
        case .week: WeekView()
        case .agreements: AgreementsView()
        case .resume: ResumeView()
        case .setup: SetupView()
        }
    }
}

struct TopBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            Spacer().frame(width: 64)
            Text("Hilo").font(.system(size: 14, weight: .bold))
            Spacer()
            HStack(spacing: 8) {
                PetView(state: buddyPet, size: 24)
                Text(buddyText).font(.system(size: 13)).foregroundStyle(Color(hex: "#c2bbb0"))
            }
            Text((model.daemonStatus?.host ?? model.config.host ?? "This Mac").capitalized).font(.system(size: 12.5)).padding(.horizontal, 10).padding(.vertical, 4)
                .background(Theme.card, in: Capsule()).overlay(Capsule().stroke(Theme.line)).foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 16).frame(height: 46).background(Theme.topBar)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var buddyText: String {
        if !model.daemonRunning { return "hilod is not running" }
        return model.buddyConnected ? "Buddy connected · BLE" : "Buddy not connected"
    }

    private var buddyPet: PetState {
        if !model.buddyConnected { return .sleep }
        return model.needsYou.isEmpty ? (model.working.isEmpty ? .idle : .working) : .alert
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                PetView(state: model.needsYou.isEmpty ? (model.working.isEmpty ? .idle : .working) : .alert, size: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your buddy").font(.system(size: 13.5, weight: .bold))
                    if !model.needsYou.isEmpty {
                        Text("\(model.needsYou.count) session\(model.needsYou.count == 1 ? "" : "s") need\(model.needsYou.count == 1 ? "s" : "") you")
                            .font(.system(size: 12)).foregroundStyle(Theme.needsYou)
                    }
                    Text(model.working.isEmpty ? "No session working" : "\(model.working.count) working")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))

            VStack(spacing: 2) {
                ForEach(AppSection.allCases) { section in
                    Button { model.section = section } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.icon).frame(width: 18)
                            Text(section.rawValue)
                            Spacer()
                            Text(badge(section)).font(.system(size: 12)).foregroundStyle(Theme.secondary).monospacedDigit()
                        }
                        .font(.system(size: 14, weight: model.section == section ? .semibold : .regular))
                        .foregroundStyle(model.section == section ? Theme.selectedText : Color(hex: "#d8d1c6"))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(model.section == section ? Theme.selected : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(text: "Projects").padding(.horizontal, 10)
                ForEach(model.projects) { p in
                    HStack(spacing: 9) {
                        ProjectDot(project: p)
                        Text(p.name).font(.system(size: 13.5))
                        Spacer()
                        Text(p.jiraKey.map { "Jira \($0)" } ?? "local").font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                }
                if model.projects.isEmpty {
                    Text("Projects appear with your first task or Claude Code session.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(.horizontal, 10)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Text("Data from this Mac only · SQLite")
                HStack(spacing: 0) {
                    Text("CLI ")
                    Text("hilo").font(Theme.mono)
                    Text(model.daemonRunning ? " · hilod running" : " · hilod stopped")
                }
            }
            .font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(.horizontal, 10)
        }
        .padding(14).frame(maxHeight: .infinity, alignment: .top).background(Theme.sidebar)
    }

    private func badge(_ section: AppSection) -> String {
        switch section {
        case .today: model.tasks.filter { $0.status != .done }.count.nonZero
        case .sessions: model.sessions.filter { $0.endedAt == nil }.count.nonZero
        case .agreements: model.pendingAgreements.count.nonZero
        case .focus: model.focusToday.count.nonZero
        case .week, .resume, .setup: ""
        }
    }
}

extension Int {
    var nonZero: String { self == 0 ? "" : "\(self)" }
}
