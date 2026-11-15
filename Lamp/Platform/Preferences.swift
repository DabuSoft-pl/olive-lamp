import Foundation
import Observation

/// The user's choices, kept in UserDefaults.
@MainActor
@Observable
final class Preferences {
    enum Key {
        static let notifyWhenDone = "notify.whenDone"
    }

    private let defaults: UserDefaults

    /// A notification when an action started here fails, or ends after a long run.
    var notifyWhenDone: Bool {
        get {
            access(keyPath: \.notifyWhenDone)
            return defaults.bool(forKey: Key.notifyWhenDone)
        }
        set {
            withMutation(keyPath: \.notifyWhenDone) { defaults.set(newValue, forKey: Key.notifyWhenDone) }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.notifyWhenDone: true])
    }
}
