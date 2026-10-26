import SwiftUI
import HiloStore

struct AgreementsView: View {
    @Environment(AppModel.self) private var model
    @State private var text = ""
    @State private var project: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Agreements").font(Theme.title(30))
                Text("Decisions you made, by date. Nothing Claude detects enters the log until you confirm it.").foregroundStyle(Theme.secondary)
            }
            HStack(spacing: 10) {
                Image(systemName: "plus").foregroundStyle(Theme.accent).fontWeight(.bold)
                TextField("Log an agreement and press ↩", text: $text).textFieldStyle(.plain).font(.system(size: 15))
                    .onSubmit {
                        model.addAgreement(text, project: project, task: nil)
                        text = ""
                    }
                ProjectPicker(selection: $project)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    let byDay = Dictionary(grouping: model.agreements.filter { $0.status == .confirmed }) {
                        Calendar.current.startOfDay(for: Date(timeIntervalSince1970: TimeInterval($0.ts)))
                    }
                    if byDay.isEmpty { Text("No agreements yet.").foregroundStyle(Theme.secondary) }
                    ForEach(byDay.keys.sorted(by: >), id: \.self) { day in
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            ForEach(byDay[day] ?? []) { row($0) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 10) {
                    HStack { SectionLabel(text: "To confirm", color: Theme.needsYou); Spacer(); Text("\(model.pendingAgreements.count)").foregroundStyle(Theme.secondary) }
                    if model.pendingAgreements.isEmpty {
                        Text("Agreements Claude proposes over MCP show up here.").font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                    }
                    ForEach(model.pendingAgreements) { a in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(a.text)
                            if !a.context.isEmpty { Text(a.context).font(.system(size: 12.5)).foregroundStyle(Theme.secondary) }
                            HStack {
                                Button("Confirm") { model.confirm(a) }.buttonStyle(PrimaryButtonStyle())
                                Button("Discard") { model.discard(a) }.buttonStyle(SecondaryButtonStyle())
                            }
                        }
                        .padding(12).background(Theme.softPanel, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(18).frame(width: 340).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
            }
        }
    }

    private func row(_ a: Agreement) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("✓").fontWeight(.bold).foregroundStyle(Color(hex: "#4fd39a"))
            VStack(alignment: .leading, spacing: 3) {
                Text(a.text)
                HStack(spacing: 10) {
                    if let p = a.project { HStack(spacing: 5) { ProjectDot(project: p); Text(p.name) } }
                    Text(a.origin.rawValue)
                    if let t = model.task(a.taskId) { Text("→ \(t.title)") }
                    Text(Format.clock(a.ts))
                }
                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            Spacer()
        }
        .padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .contextMenu { Button("Delete", role: .destructive) { model.discard(a) } }
    }
}
