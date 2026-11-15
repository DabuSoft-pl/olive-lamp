import AppKit
import SwiftUI

@main
struct LampApp: App {
    @State private var container: AppContainer

    init() {
        let container = AppContainer.live()
        container.start()
        #if DEBUG
        if let folder = Snapshot.folder { Snapshot.run(container, into: folder) }
        #endif
        _container = State(initialValue: container)
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: container.panel, actions: container.panelActions)
        } label: {
            MenuBarLabel(panel: container.panel, statusMenu: container.statusMenu)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(servers: container.servers, preferences: container.preferences)
        }
    }
}

/// The lamp in the menu bar. It also hands the right-click menu a way to open Settings, which only a view has.
private struct MenuBarLabel: View {
    let panel: PanelViewModel
    let statusMenu: StatusItemMenu
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(nsImage: LampMark.image(for: panel.barState))
            .onAppear { [openSettings] in
                statusMenu.openSettings = { SettingsWindow.open(with: openSettings) }
            }
    }
}
