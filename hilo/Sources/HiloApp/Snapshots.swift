import AppKit
import SwiftUI

/// Development aid: with `HILO_SNAPSHOT=<dir>`, saves a PNG of every section and quits.
enum Snapshots {
    /// `cacheDisplay` draws neither Liquid Glass nor materials, so snapshots use flat colors.
    static let requested = ProcessInfo.processInfo.environment["HILO_SNAPSHOT"] != nil

    @MainActor
    static func runIfRequested(_ model: AppModel) async {
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
