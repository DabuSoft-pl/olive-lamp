import Foundation
import LampDomain

/// The servers the user added, which one the panel shows, and a gateway to it.
@MainActor
public final class ServerDirectory {
    private let repository: any ServerRepository
    private let credentials: any CredentialStore
    private let gateways: any GatewayMaking
    public private(set) var servers: [Server]
    public private(set) var selectedID: UUID?

    public init(repository: any ServerRepository, credentials: any CredentialStore, gateways: any GatewayMaking) {
        self.repository = repository
        self.credentials = credentials
        self.gateways = gateways
        servers = (try? repository.load()) ?? []
        selectedID = servers.first?.id
    }

    public var selected: Server? { servers.first { $0.id == selectedID } ?? servers.first }

    public func select(_ id: UUID) {
        guard servers.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    public func gateway(for server: Server) -> any OliveTinGateway {
        gateways.gateway(address: server.address, credential: credential(for: server))
    }

    /// The saved credential, only while the server's address has the origin it was given for. `servers.json` is a plain
    /// file, so an address changed outside Lamp gets no secret until the user signs in to it again.
    private func credential(for server: Server) -> Credential? {
        guard let stored = try? credentials.credential(for: server.id) else { return nil }
        guard let origin = stored.origin else {
            // Saved before origins were kept: bound to the address it is used with now.
            try? credentials.store(stored.credential, origin: server.address.origin, for: server.id)
            return stored.credential
        }
        return origin == server.address.origin ? stored.credential : nil
    }

    /// A gateway to an address that is not saved yet, for probing it.
    public func gateway(address: URL, credential: Credential?) -> any OliveTinGateway {
        gateways.gateway(address: address, credential: credential)
    }

    public func add(_ server: Server, credential: Credential?) throws {
        try updateCredential(credential, for: server)
        servers.append(server)
        try repository.save(servers)
        selectedID = server.id
    }

    public func updateCredential(_ credential: Credential?, for server: Server) throws {
        if let credential {
            try credentials.store(credential, origin: server.address.origin, for: server.id)
        } else {
            try credentials.remove(for: server.id)
        }
    }

    /// Saves a changed server (its name, address or entity type); the credential stays as it is.
    public func update(_ server: Server) throws {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[index] = server
        try repository.save(servers)
    }

    public func remove(_ id: UUID) throws {
        try credentials.remove(for: id)
        servers.removeAll { $0.id == id }
        try repository.save(servers)
        if selectedID == id { selectedID = servers.first?.id }
    }
}
