import SwiftUI
import HiloContract
import HiloStore

struct SessionsView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = Filter.all

    enum Filter: String, CaseIterable { case all = "All", active = "Active", needYou = "Need you", finished = "Finished today" }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude Code sessions").font(Theme.title(30))
                    Text("This Mac only · captured by the Claude Code hook").foregroundStyle(Theme.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(Filter.allCases, id: \.self) { f in
                        Button("\(f.rawValue) · \(rows(f).count)") { filter = f }
                            .buttonStyle(.plain).font(.system(size: 12.5, weight: .semibold))
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(filter == f ? Theme.selected : Theme.card, in: Capsule())
                            .overlay(Capsule().stroke(filter == f ? Theme.selectedBorder : Theme.line))
                            .foregroundStyle(filter == f ? Theme.selectedText : Theme.text)
                    }
                }
            }
            ForEach(model.needsYou) { banner($0) }
            table
            if let session = model.sessions.first(where: { $0.id == model.selectedSession }) ?? rows(filter).first {
                HStack(alignment: .top, spacing: 20) {
                    SessionDetail(session: session).frame(maxWidth: .infinity)
                    CapturePanel().frame(width: 320)
                }
            } else {
                CapturePanel().frame(maxWidth: 420)
            }
        }
    }

    private func rows(_ f: Filter) -> [SessionRecord] {
        switch f {
        case .all: model.sessions
        case .active: model.sessions.filter { $0.endedAt == nil && ($0.status == .working || $0.status == .waiting) }
        case .needYou: model.needsYou
        case .finished: model.sessions.filter { $0.endedAt != nil || $0.status == .done }
        }
    }

    private func banner(_ s: SessionRecord) -> some View {
        HStack(spacing: 14) {
            PetView(look: PetView.look(of: s), state: .alert, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(s.project?.name ?? "A session") needs you").fontWeight(.bold)
                HStack(spacing: 0) {
                    Text(s.waitingOn ?? s.lastAction).font(Theme.monospaced(13))
                    Text(" · also shown on the buddy when you are away from the Mac")
                }
                .font(.system(size: 13.5)).foregroundStyle(Color(hex: "#e6cf94")).lineLimit(1)
            }
            Spacer()
        }
        .padding(14).background(Color(hex: "#2b2210"), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#5c4716")))
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Project").frame(width: 220, alignment: .leading)
                Text("Status").frame(width: 100, alignment: .leading)
                Text("Hilo task").frame(maxWidth: .infinity, alignment: .leading)
                Text("Duration").frame(width: 90, alignment: .trailing)
                Text("Tokens").frame(width: 90, alignment: .trailing).padding(.trailing, 8)
                Text("Last action").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 11.5, weight: .semibold)).tracking(0.8).textCase(.uppercase).foregroundStyle(Theme.secondary)
            .padding(.horizontal, 16).padding(.vertical, 12)
            if rows(filter).isEmpty {
                Text(model.daemonRunning ? "No sessions yet today. They appear as soon as Claude Code sends a hook to hilod."
                                         : "hilod is not running, so no sessions are being captured.")
                    .foregroundStyle(Theme.secondary).padding(20).frame(maxWidth: .infinity)
            }
            ForEach(rows(filter)) { s in
                let selected = s.id == model.selectedSession
                HStack(spacing: 8) {
                    HStack(spacing: 10) {
                        PetView(look: PetView.look(of: s), state: PetState(s.status), size: 32)
                        Text(s.project?.name ?? String(s.id.prefix(8))).font(Theme.monospaced(13, .medium))
                    }
                    .frame(width: 220, alignment: .leading)
                    StatusChip(status: s.status).frame(width: 100, alignment: .leading)
                    Text(s.taskTitle ?? "—").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(Format.duration(Format.sessionTime(s))).monospacedDigit().frame(width: 90, alignment: .trailing)
                    Text(s.tokens.map(Format.tokens) ?? "—").monospacedDigit().frame(width: 90, alignment: .trailing).padding(.trailing, 8)
                    Text(s.lastAction).foregroundStyle(Color(hex: "#c2bbb0")).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(selected ? Theme.selected.opacity(0.6) : .clear)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                .contentShape(Rectangle())
                .onTapGesture { model.selectedSession = s.id }
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }
}

struct SessionDetail: View {
    @Environment(AppModel.self) private var model
    let session: SessionRecord

    static func accessoryName(_ acc: Accessory) -> String {
        switch acc {
        case .none: "None"
        case .wizard: "Wizard hat"
        case .shades: "Shades"
        case .headphones: "Headphones"
        case .crown: "Crown"
        case .party: "Party hat"
        case .band: "Headband"
        case .heart: "Heart"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                PetView(look: PetView.look(of: session), state: PetState(session.status), size: 54)
                Text(session.project?.name ?? "Session").font(Theme.title(22)).lineLimit(1).fixedSize()
                Menu {
                    ForEach(Accessory.allCases, id: \.self) { acc in
                        Button(Self.accessoryName(acc)) { model.setLook(session, acc: acc) }
                    }
                } label: {
                    Text("Pet: \(Self.accessoryName(PetView.look(of: session).accessory))")
                }
                .menuStyle(.borderlessButton).fixedSize().foregroundStyle(Theme.link)
                .help("Same colour family as the rest of the project; the accessory tells its sessions apart, here and on the buddy.")
                Spacer(minLength: 12)
                Menu {
                    Button("No task") { model.link(session: session.id, task: nil) }
                    ForEach(model.tasks.filter { $0.status != .done }) { t in
                        Button(t.title) { model.link(session: session.id, task: t.id) }
                    }
                } label: {
                    Text(session.taskTitle.map { "Linked to \($0)" } ?? "Link to a task").lineLimit(1).truncationMode(.tail)
                }
                .menuStyle(.borderlessButton).frame(maxWidth: 320, alignment: .trailing).foregroundStyle(Theme.link)
            }
            VStack(alignment: .leading, spacing: 0) {
                let steps = model.steps(session.id)
                if steps.isEmpty { Text("No steps recorded yet.").foregroundStyle(Theme.secondary) }
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    HStack(spacing: 12) {
                        Text(Format.clock(step.ts)).font(Theme.monospaced(12)).foregroundStyle(Theme.secondary)
                            .lineLimit(1).fixedSize().frame(minWidth: 70, alignment: .leading)
                        RoundedRectangle(cornerRadius: 2.5).fill(Theme.stepColor[step.kind] ?? Theme.secondary).frame(width: 9, height: 9)
                        Text(step.text).lineLimit(2)
                    }
                    .padding(.vertical, 6)
                }
            }
            HStack {
                let command = "claude --resume \(session.id)"
                Text(command).font(Theme.mono).textSelection(.enabled).lineLimit(1)
                Spacer()
                CopyButton("Copy command") { command }.buttonStyle(SecondaryButtonStyle())
            }
            .padding(10).background(Theme.softPanel, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(20).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }
}

struct CapturePanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Automatic capture").font(Theme.title(18))
            item(model.daemonRunning, "Claude Code sessions", model.daemonRunning ? "hilod receives every hook from this Mac" : "Start hilod to capture sessions")
            item(model.buddyConnected, "Buddy", model.buddyConnected ? "Connected over BLE" : "Not connected")
            let commitsToday = model.weekCommits.filter { $0.ts >= AppModel.startOfToday }.count
            item(model.daemonRunning, "Git commits", "\(commitsToday) today in this Mac's session repos")
            item(model.daemonRunning, "Active time", "\(Format.duration(model.activeToday.values.reduce(0, +))) today · pauses after 5 min idle")
        }
        .padding(20).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }

    private func item(_ on: Bool, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(on ? Color(hex: "#4fd39a") : Color(hex: "#5a554e")).frame(width: 9, height: 9).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
        }
    }
}
