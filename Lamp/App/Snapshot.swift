#if DEBUG
import AppKit
import SwiftUI

/// `"Olive Lamp.app/Contents/MacOS/Olive Lamp" -snapshot <folder>` renders the panel in both appearances to PNG files and quits.
/// For checking the design against docs/design without clicking the menu bar; Debug builds only.
@MainActor
enum Snapshot {
    static var folder: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-snapshot"), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    static func run(_ container: AppContainer, into folder: URL) {
        Task {
            try? await Task.sleep(for: .seconds(3))
            for (name, scheme) in [("panel-dark", ColorScheme.dark), ("panel-light", .light)] {
                let view = PanelView(model: container.panel, actions: container.panelActions, preferences: container.preferences, scrolls: false)
                    .background(scheme == .dark ? Color(white: 0.08) : Color(white: 0.98))
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: folder.appending(path: "\(name).png"))
                }
            }
            NSApp.terminate(nil)
        }
    }
}
#endif
