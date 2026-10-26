import AppKit
import SwiftUI

/// Development aid: with `HILO_SNAPSHOT=<dir>`, saves a PNG of every section and quits.
enum Snapshots {
    @MainActor
    static func runIfRequested(_ model: AppModel) async {
        guard let dir = ProcessInfo.processInfo.environment["HILO_SNAPSHOT"] else { return }
        try? await Task.sleep(for: .seconds(1.5))
        for section in AppSection.allCases {
            model.section = section
            try? await Task.sleep(for: .seconds(1))
            guard let view = NSApp.windows.first(where: \.isVisible)?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            let name = section.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appending(path: "\(name).png"))
        }
        NSApp.terminate(nil)
    }
}
