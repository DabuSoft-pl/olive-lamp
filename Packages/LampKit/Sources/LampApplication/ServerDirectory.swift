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
        gateways.gateway(address: server.address, credential: try? credentials.credential(for: server.id))
    }

    /// A gateway to an address that is not saved yet, for probing it.
    public func gateway(address: URL, credential: Credential?) -> any OliveTinGateway {
        gateways.gateway(address: address, credential: credential)
    }

    public func add(_ server: Server, credential: Credential?) throws {
        if let credential {
            try credentials.store(credential, for: server.id)
        } else {
            try credentials.remove(for: server.id)
        }
        servers.append(server)
        try repository.save(servers)
        selectedID = server.id
    }

    public func updateCredential(_ credential: Credential?, for server: Server) throws {
        if let credential {
            try credentials.store(credential, for: server.id)
        } else {
            try credentials.remove(for: server.id)
        }
    }

    public func remove(_ id: UUID) throws {
        try credentials.remove(for: id)
        servers.removeAll { $0.id == id }
        try repository.save(servers)
        if selectedID == id { selectedID = servers.first?.id }
    }
}
