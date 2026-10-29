import AppKit
import SwiftUI

/// Development aid: with `HILO_SNAPSHOT=<dir>`, saves a PNG of every section and quits.
enum Snapshots {
    /// `cacheDisplay` draws neither Liquid Glass nor materials, so snapshots use flat colors.
    static let requested = ProcessInfo.processInfo.environment["HILO_SNAPSHOT"] != nil

    @MainActor
    static func runIfRequested(_ model: AppModel) async {
        if let path = ProcessInfo.processInfo.environment["HILO_ICON"] {
            saveIcon(to: URL(fileURLWithPath: path))
            NSApp.terminate(nil)
            return
        }
        guard let dir = ProcessInfo.processInfo.environment["HILO_SNAPSHOT"] else { return }
        try? await Task.sleep(for: .seconds(1.5))
        for section in AppSection.allCases {
            model.section = section
            try? await Task.sleep(for: .seconds(1))
            guard let view = NSApp.windows.first(where: \.isVisible)?.contentView?.superview else { continue }
            let name = section.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
            save(view, to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
            if let page = tallestScroll(in: view)?.documentView, page.bounds.height > view.bounds.height {
                save(page, to: URL(fileURLWithPath: dir).appending(path: "\(name)-full.png"))
            }
        }
        NSApp.terminate(nil)
    }

    /// With `HILO_ICON=<png>`: the 1024 px source of the app icon (scripts/make-app-icon.sh).
    @MainActor
    private static func saveIcon(to url: URL) {
        let renderer = ImageRenderer(content: AppIconArt())
        renderer.scale = 1
        guard let image = renderer.cgImage else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }

    @MainActor
    private static func save(_ view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// The section's own scroll view: the one with the tallest content.
    @MainActor
    private static func tallestScroll(in view: NSView) -> NSScrollView? {
        var best = view as? NSScrollView
        for sub in view.subviews {
            if let found = tallestScroll(in: sub),
               (found.documentView?.bounds.height ?? 0) > (best?.documentView?.bounds.height ?? 0) { best = found }
        }
        return best
    }
}

/// Claudio on a dark squircle, sized to macOS's icon grid (824 px plate in a 1024 px canvas).
struct AppIconArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#2b2520"), Color(hex: "#12100e")], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 185, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 4))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
            PetView(state: .idle, size: 640, frozenAt: 0).offset(y: -40)
        }
        .frame(width: 1024, height: 1024)
    }
}
