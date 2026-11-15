import Foundation
import LampApplication
import LampDomain

/// Adding, checking and removing servers from Settings.
@MainActor
final class ServersController {
    private let directory: ServerDirectory
    private let probe: ProbeServer
    private let addServer: AddServer
    private let signInAgain: SignInAgain
    private let panel: PanelController

    init(directory: ServerDirectory, probe: ProbeServer, addServer: AddServer, signInAgain: SignInAgain, panel: PanelController) {
        self.directory = directory
        self.probe = probe
        self.addServer = addServer
        self.signInAgain = signInAgain
        self.panel = panel
    }

    var servers: [Server] { directory.servers }

    func check(address: URL, credential: Credential?) async throws(GatewayError) -> ServerInfo {
        try await probe(address: address, credential: credential)
    }

    func add(name: String, address: URL, signIn: SignInMethod, credential: Credential?) async throws(GatewayError) {
        _ = try await addServer(name: name, address: address, signIn: signIn, credential: credential)
        panel.syncServers()
        panel.refresh()
    }

    func signIn(_ server: Server, with credential: Credential) async throws(GatewayError) {
        try await signInAgain(server, credential: credential)
        panel.refresh()
    }

    func remove(_ server: Server) {
        try? directory.remove(server.id)
        panel.syncServers()
        panel.refresh()
    }

    /// "panel.example.ts.net" becomes "https://panel.example.ts.net"; anything that is not a web address is nil.
    static func address(from text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(), !host.isEmpty else { return nil }
        return url
    }
}
