#if DEBUG
import AppKit
import LampApplication
import LampDomain
import SwiftUI

/// `"Olive Lamp.app/Contents/MacOS/Olive Lamp" -screenshots <folder>` (Debug builds) renders the README images from
/// made-up homelab data, through real AppKit windows so menus and pickers draw as they do on screen, and quits.
@MainActor
enum Screenshots {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "-screenshots"), arguments.indices.contains(index + 1) else { return }
        let folder = URL(fileURLWithPath: arguments[index + 1])
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for running in [false, true] {
            let container = AppContainer(
                repository: DemoServers(), credentials: DemoCredentials(), gateways: DemoGateways(running: running),
                clock: DemoClock(), preferences: Preferences()
            )
            container.panelActions.refresh()
            RunLoop.main.run(until: Date().addingTimeInterval(1))
            for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                let panel = PanelView(
                    model: container.panel, actions: container.panelActions, preferences: container.preferences,
                    updates: container.updates, scrolls: false
                )
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                let file = running ? "running-\(name).png" : "panel-\(name).png"
                render(panel, width: 440, appearance: appearance, to: folder.appending(path: file))
            }
        }
        exit(0)
    }

    private static func render(_ view: some View, width: CGFloat, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view.frame(width: width).fixedSize(horizontal: false, vertical: true))
        host.appearance = NSAppearance(named: appearance)
        let frame = CGRect(origin: .zero, size: CGSize(width: width, height: max(host.fittingSize.height, 10)))
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = host
        host.frame = frame
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

private final class DemoServers: ServerRepository, @unchecked Sendable {
    func load() throws -> [Server] {
        [Server(name: "Homelab", address: URL(string: "https://olivetin.example.net")!, signIn: .automatic)]
    }

    func save(_ servers: [Server]) throws {}
}

private final class DemoCredentials: CredentialStore, @unchecked Sendable {
    func credential(for server: UUID) throws -> Credential? { nil }
    func store(_ credential: Credential, for server: UUID) throws {}
    func remove(for server: UUID) throws {}
}

private struct DemoClock: Clock {
    var now: Date { Date() }
    func sleep(seconds: Double) async throws { try await Task.sleep(for: .seconds(seconds)) }
}

private final class DemoGateways: GatewayMaking, @unchecked Sendable {
    let running: Bool
    init(running: Bool) { self.running = running }
    func gateway(address: URL, credential: Credential?) -> any OliveTinGateway { DemoGateway(running: running) }
}

/// A small homelab: a Proxmox host, its guests and a NAS that wants updates, with a package update running.
private struct DemoGateway: OliveTinGateway {
    let running: Bool
    private static let started = Date().addingTimeInterval(-48)

    func info() async throws -> ServerInfo {
        ServerInfo(
            title: "OliveTin", version: "3000.22.0", user: "admin", loginRequired: false, offersLocalLogin: false,
            oAuthProviders: [], rootDashboards: ["Homelab"]
        )
    }

    func actions(dashboards: [String]) async throws -> [Action] {
        let confirm = ActionArgument(name: "confirm", title: "Sure?", kind: .confirmation)
        let hosts = ActionArgument(name: "limit", title: "Machine", kind: .choice(
            ["all", "pve", "nas", "jellyfin", "home-assistant"].map { ActionArgument.Choice(value: $0, title: $0) }
        ), defaultValue: "all")
        return [
            Action(id: "check", title: "Check machines", group: "Everyday", arguments: [hosts]),
            Action(id: "update", title: "Update packages", group: "Everyday", isRunning: running, arguments: [hosts, confirm]),
            Action(id: "jellyfin", title: "Restart Jellyfin", group: "Everyday", arguments: [confirm]),
            Action(id: "wake", title: "Wake the NAS", group: "Everyday"),
            Action(id: "photos", title: "Back up photos", group: "Backups"),
            Action(id: "verify", title: "Verify backup archive", group: "Backups"),
            Action(id: "prune", title: "Prune Docker", group: "Maintenance", arguments: [confirm]),
            Action(id: "certs", title: "Renew certificates", group: "Maintenance"),
        ]
    }

    func entityTypes() async throws -> [String] { ["machine", "container"] }

    func machines(entityType: String) async throws -> [Machine] {
        [
            Machine(id: "pve", name: "pve", kind: "host", health: .ok),
            Machine(id: "nas", name: "nas", kind: "vm", health: .attention, note: "3 updates"),
            Machine(id: "jellyfin", name: "jellyfin", kind: "lxc", health: .ok),
            Machine(id: "ha", name: "home-assistant", kind: "vm", health: .ok),
            Machine(id: "router", name: "router", kind: "lxc", health: .ok),
            Machine(id: "test", name: "test", kind: "vm", health: .off),
        ]
    }

    func relatedActions(entityType: String, key: String) async throws -> [Action] {
        [Action(id: "restart-\(key)", title: "Restart \(key)"), Action(id: "update-\(key)", title: "Update \(key)")]
    }

    func start(actionID: String, arguments: [String: String], justification: String?) async throws -> String { "run" }

    func execution(id: String) async throws -> Execution { Self.running }

    func history() async throws -> [Execution] {
        (running ? [Self.running] : []) + (1...3).map { day in
            let start = Date().addingTimeInterval(Double(-86_400 * day))
            return Execution(
                id: "past-\(day)", actionID: "update", actionTitle: "Update packages", user: "admin", startedAt: start,
                finishedAt: start.addingTimeInterval(70 + Double(day * 4)), isFinished: true
            )
        }
    }

    func stop(executionID: String) async throws {}

    private static let running = Execution(
        id: "run", actionID: "update", actionTitle: "Update packages", user: "admin", startedAt: started,
        output: """
        PLAY [all] *********************************************************************
        TASK [Refresh the package cache] ***********************************************
        ok: [pve]
        ok: [nas]
        TASK [Upgrade packages] ********************************************************
        changed: [jellyfin]
        """,
        canKill: true
    )
}
#endif
