import AppKit

/// Receives `olivelamp://` links (from the Raycast extension). The handler goes in once AppKit finished launching,
/// so its own handler for the same event does not replace it.
@MainActor
final class LinkReceiver: NSObject {
    private let onURL: (URL) -> Void
    private var observer: (any NSObjectProtocol)?

    init(onURL: @escaping (URL) -> Void) {
        self.onURL = onURL
    }

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.install() }
        }
    }

    private func install() {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handle(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handle(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: text) else { return }
        onURL(url)
    }
}
