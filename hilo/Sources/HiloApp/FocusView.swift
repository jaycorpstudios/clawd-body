import SwiftUI
import HiloContract
import HiloCore

/// Pomodoro shared with the buddy through `hilod`: either side can start, pause or reset it.
struct FocusView: View {
    @Environment(AppModel.self) private var model

    private var focus: PomodoroState { model.daemonStatus?.pomodoro ?? .stopped(now: 0) }
    private var enabled: Bool { model.daemonRunning }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Focus").font(Theme.title(30))
                Text("A Pomodoro shared with the buddy: start it here or on its Focus view, and both follow. It keeps running on the buddy when the link drops.")
                    .foregroundStyle(Theme.secondary)
            }
            if !enabled {
                Text("Start hilod in Setup to use the timer.").foregroundStyle(Theme.needsYou)
            }
            HStack(alignment: .top, spacing: 24) {
                timer.frame(maxWidth: .infinity)
                side.frame(width: 300)
            }
        }
    }

    private var timer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = Int(context.date.timeIntervalSince1970)
            var p = focus
            let _ = p.advance(to: now)
            VStack(spacing: 18) {
                PetView(look: .main, state: pet(p), size: 128)
                Text(phaseLabel(p)).font(Theme.sectionLabel).tracking(2).foregroundStyle(p.state == .stopped ? Theme.secondary : color(p))
                Text(clock(p.left(now: now))).font(Theme.monospaced(64)).monospacedDigit()
                ProgressView(value: progress(p, now: now)).tint(color(p)).frame(maxWidth: 360)
                HStack(spacing: 10) {
                    Button(p.state == .running ? "Pause" : p.state == .paused ? "Resume" : "Start") { model.pomodoro(["action": "toggle"]) }
                        .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.space, modifiers: [])
                    Button("Reset") { model.pomodoro(["action": "reset"]) }.buttonStyle(SecondaryButtonStyle())
                }
                .disabled(!enabled)
            }
            .padding(28).frame(maxWidth: .infinity)
            .background(tint(p).fill, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(tint(p).edge))
        }
    }

    private func tint(_ p: PomodoroState) -> (fill: Color, edge: Color) {
        guard p.state == .running else { return (Theme.card, Theme.line) }
        return p.phase == .work ? (Theme.focusWork, Theme.focusWorkEdge) : (Theme.focusBreak, Theme.focusBreakEdge)
    }

    private var side: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Durations")
                stepper("Work", value: focus.workMin, range: 1...90, step: 5, key: "work_min")
                stepper("Break", value: focus.breakMin, range: 1...60, step: 1, key: "break_min")
                if focus.state != .stopped {
                    Text("Reset to change them.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Today")
                Text("\(model.focusToday.count) cycle\(model.focusToday.count == 1 ? "" : "s") · \(model.focusToday.minutes) min")
                    .font(.system(size: 15, weight: .semibold))
                if let task = model.tasks.first(where: { $0.status == .doing }) {
                    Text("Finished cycles count for “\(task.title)”, the task in progress.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                } else {
                    Text("Start a task in Today to link the cycles to it.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }

    private func stepper(_ name: String, value: Int, range: ClosedRange<Int>, step: Int, key: String) -> some View {
        HStack {
            Text(name)
            Spacer()
            Button { set(key, max(range.lowerBound, value - step)) } label: { Image(systemName: "minus") }.buttonStyle(SecondaryButtonStyle())
            Text("\(value) min").font(Theme.mono).frame(width: 64)
            Button { set(key, min(range.upperBound, value + step)) } label: { Image(systemName: "plus") }.buttonStyle(SecondaryButtonStyle())
        }
        .disabled(!enabled || focus.state != .stopped)
    }

    private func set(_ key: String, _ value: Int) { model.pomodoro(["action": "durations", key: value]) }

    private func pet(_ p: PomodoroState) -> PetState {
        guard p.state == .running else { return .idle }
        return p.phase == .work ? .working : .happy
    }

    private func color(_ p: PomodoroState) -> Color { p.phase == .work ? Theme.progress : Theme.doneCheck }

    private func phaseLabel(_ p: PomodoroState) -> String {
        let phase = p.phase == .work ? "Work" : "Break"
        return p.state == .paused ? "\(phase) · paused" : phase
    }

    private func clock(_ s: Int) -> String { String(format: "%02d:%02d", s / 60, s % 60) }

    private func progress(_ p: PomodoroState, now: Int) -> Double {
        let total = Double((p.phase == .work ? p.workMin : p.breakMin) * 60)
        return min(1, max(0, 1 - Double(p.left(now: now)) / total))
    }
}
