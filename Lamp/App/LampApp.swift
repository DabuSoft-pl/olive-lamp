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
            Image(nsImage: LampMark.image(for: container.panel.barState))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(servers: container.servers, preferences: container.preferences)
        }
    }
}
