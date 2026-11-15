import Foundation
import LampApplication
import LampDomain
import UserNotifications

/// Tells the user how a run ended, when it failed or took long enough to look away.
@MainActor
final class UserNotificationsAdapter: NSObject, RunNotifying, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var asked = false

    override init() {
        super.init()
        center.delegate = self
    }

    func notifyFinished(_ execution: Execution, server: String) {
        guard execution.deservesNotice() else { return }
        let content = UNMutableNotificationContent()
        let duration = Clockface.duration(execution.duration ?? 0)
        switch execution.state {
        case .succeeded:
            content.title = String(localized: "\(execution.actionTitle) finished")
            content.body = String(localized: "\(server) · in \(duration)")
        case .timedOut:
            content.title = String(localized: "\(execution.actionTitle) timed out")
            content.body = String(localized: "\(server) · after \(duration)")
        default:
            content.title = String(localized: "\(execution.actionTitle) failed")
            content.body = String(localized: "\(server) · exit code \(execution.exitCode) after \(duration)")
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: execution.id, content: content, trigger: nil)
        Task {
            if !asked {
                asked = true
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            try? await center.add(request)
        }
    }

    /// A menu bar app counts as active while its panel is open; show the banner anyway.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
