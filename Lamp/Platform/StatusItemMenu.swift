import AppKit
import LampDomain

/// A right click on the lamp opens a short menu (refresh, the servers, the browser, Settings, Quit); a left click still
/// opens the panel. SwiftUI's `MenuBarExtra` has no context menu, so a local monitor takes right clicks on the item's
/// own window and lets every other event through untouched.
@MainActor
final class StatusItemMenu: NSObject {
    /// Set by a SwiftUI view, since only a view can open the Settings scene.
    var openSettings: (() -> Void)?
    private let panel: PanelViewModel
    private let actions: PanelController
    private let updates: SoftwareUpdate
    private var monitor: Any?

    init(panel: PanelViewModel, actions: PanelController, updates: SoftwareUpdate) {
        self.panel = panel
        self.actions = actions
        self.updates = updates
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, let window = event.window, Self.isStatusItem(window), let button = window.contentView else {
                return event
            }
            self.show(under: button)
            return nil
        }
    }

    /// Local events only reach this app's windows, so a status bar window here is Olive Lamp's own item.
    private static func isStatusItem(_ window: NSWindow) -> Bool {
        String(describing: type(of: window)).contains("StatusBarWindow")
    }

    private func show(under button: NSView) {
        let menu = NSMenu()
        let hasServer = !panel.servers.isEmpty
        if hasServer {
            menu.addItem(item(String(localized: "Refresh"), action: #selector(refresh), key: "r"))
            menu.addItem(item(String(localized: "Open in Browser"), action: #selector(openInBrowser)))
        }
        if panel.servers.count > 1 {
            menu.addItem(.separator())
            for server in panel.servers {
                let entry = item(server.name, action: #selector(select(_:)))
                entry.representedObject = server.id
                entry.state = server.id == panel.selectedServer ? .on : .off
                menu.addItem(entry)
            }
        }
        if hasServer { menu.addItem(.separator()) }
        if openSettings != nil {
            menu.addItem(item(String(localized: "Settings…"), action: #selector(settings), key: ","))
        }
        if updates.isAvailable {
            menu.addItem(item(String(localized: "Check for Updates…"), action: #selector(checkForUpdates)))
        }
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Quit Olive Lamp"), action: #selector(quit), key: "q"))
        let y = button.isFlipped ? button.bounds.maxY + 4 : -4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: button)
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func refresh() { actions.refresh() }

    @objc private func openInBrowser() { actions.openInBrowser() }

    @objc private func select(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let server = panel.servers.first(where: { $0.id == id }) else { return }
        actions.select(server)
    }

    @objc private func settings() { openSettings?() }

    @objc private func checkForUpdates() { updates.checkNow() }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
