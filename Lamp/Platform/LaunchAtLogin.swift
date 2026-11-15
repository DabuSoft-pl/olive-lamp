import Observation
import ServiceManagement

/// Opening Lamp at login, through the system's own login items. Only the user's toggle in Settings changes it.
@MainActor
@Observable
final class LaunchAtLogin {
    enum State: Equatable {
        case disabled, enabled, requiresApproval
    }

    private(set) var state: State = .disabled
    private(set) var error: String?

    init() {
        refresh()
    }

    var isOn: Bool { state != .disabled }

    /// System Settings can change it behind Lamp's back, so Settings rereads it when it appears.
    func refresh() {
        state = switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        default: .disabled
        }
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            error = nil
        } catch {
            self.error = String(localized: "Could not change the login item: \(error.localizedDescription)")
        }
        refresh()
    }
}
