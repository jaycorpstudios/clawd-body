import Foundation
import HiloContract
import UserNotifications

/// The Mac side of the buddy's end-of-phase alarm. macOS asks for permission the first time one is shown.
@MainActor
enum PhaseNotifier {
    private static let presenter = Presenter()

    static func announce(_ state: PomodoroState) {
        guard !Snapshots.requested, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        if state.phase == .rest {
            content.title = "Break time"
            content.body = "\(state.workMin) min of focus done. Take \(state.breakMin)."
        } else {
            content.title = "Back to work"
            content.body = "Break over. Next: \(state.workMin) min of focus."
        }
        content.sound = .default
        let center = UNUserNotificationCenter.current()
        center.delegate = presenter
        let request = UNNotificationRequest(identifier: "dev.hilo.focus", content: content, trigger: nil)
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            try? await center.add(request)
        }
    }

    /// Without it macOS hides the banner while Hilo is the frontmost app.
    private final class Presenter: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
            async -> UNNotificationPresentationOptions { [.banner, .sound] }
    }
}
