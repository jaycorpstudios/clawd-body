import SwiftUI

struct Toast: Equatable, Identifiable {
    enum Kind { case done, info, error }

    let id = UUID()
    var kind: Kind
    var text: String

    /// Errors stay long enough to read a path or a command in them.
    var seconds: Double { kind == .error ? 12 : 2.5 }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    let toast: Toast

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 14, weight: .semibold))
            Text(toast.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if toast.kind == .error {
                Button { model.toast = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(Theme.secondary).help("Dismiss")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: 520, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.5)))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .task(id: toast.id) {
            try? await Task.sleep(for: .seconds(toast.seconds))
            if model.toast?.id == toast.id { model.toast = nil }
        }
    }

    private var icon: String {
        switch toast.kind {
        case .done: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch toast.kind {
        case .done: Theme.doneCheck
        case .info: Theme.link
        case .error: Color(hex: "#ff9a9d")
        }
    }
}
