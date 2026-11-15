import Foundation
import LampDomain

/// The OliveTin API of one server, already signed in the way the server expects.
public protocol OliveTinGateway: Sendable {
    func info() async throws -> ServerInfo
    /// Every action on the given dashboards, in dashboard order.
    func actions(dashboards: [String]) async throws -> [Action]
    /// The entity types that have at least one entity, in the server's order.
    func entityTypes() async throws -> [String]
    /// The entities of one type, each read as a machine.
    func machines(entityType: String) async throws -> [Machine]
    /// The actions OliveTin offers for one entity, with their preset arguments.
    func relatedActions(entityType: String, key: String) async throws -> [Action]
    /// Starts an action and returns its execution tracking id.
    /// `justification` is the user's reason, for an action that asks for one.
    func start(actionID: String, arguments: [String: String], justification: String?) async throws -> String
    func execution(id: String) async throws -> Execution
    /// The newest runs first.
    func history() async throws -> [Execution]
    func stop(executionID: String) async throws
}

public enum GatewayError: Error, Equatable, Sendable {
    /// No answer: wrong address, the server is down, or the network (Tailscale) is off.
    case unreachable(String)
    /// The server, or a proxy in front of it, wants the user to sign in (again).
    case signInNeeded
    /// Something answered, but not OliveTin's API.
    case notOliveTin
    /// OliveTin refused, with its own message.
    case refused(String)
}

public protocol GatewayMaking: Sendable {
    func gateway(address: URL, credential: Credential?) -> any OliveTinGateway
}

public protocol ServerRepository: Sendable {
    func load() throws -> [Server]
    func save(_ servers: [Server]) throws
}

/// Keeps API keys, headers and session cookies. Only the Keychain implements it for real.
public protocol CredentialStore: Sendable {
    func credential(for server: UUID) throws -> Credential?
    func store(_ credential: Credential, for server: UUID) throws
    func remove(for server: UUID) throws
}

public protocol Clock: Sendable {
    var now: Date { get }
    func sleep(seconds: Double) async throws
}

/// Everything the panel shows about the selected server.
public struct Overview: Equatable, Sendable {
    public var server: Server
    public var info: ServerInfo
    public var actions: [Action]
    public var machines: [Machine]
    /// The entity types the server offers, and the one `machines` are of (nil: none listed).
    public var entityTypes: [String]
    public var entityType: String?
    /// The newest runs first.
    public var history: [Execution]
    public var checkedAt: Date

    public init(
        server: Server, info: ServerInfo, actions: [Action], machines: [Machine], entityTypes: [String] = [],
        entityType: String? = nil, history: [Execution], checkedAt: Date
    ) {
        self.server = server
        self.info = info
        self.actions = actions
        self.machines = machines
        self.entityTypes = entityTypes
        self.entityType = entityType
        self.history = history
        self.checkedAt = checkedAt
    }
}

/// A run being followed, with what the app expects of it.
public struct RunProgress: Equatable, Sendable {
    public var execution: Execution
    public var estimate: RunEstimate?

    public init(execution: Execution, estimate: RunEstimate?) {
        self.execution = execution
        self.estimate = estimate
    }
}

@MainActor
public protocol OverviewOutput: AnyObject {
    func show(_ overview: Overview)
    func showProblem(_ problem: GatewayError, server: Server)
    func showNoServer()
}

@MainActor
public protocol RunOutput: AnyObject {
    func show(_ run: RunProgress)
    func showStartFailed(_ problem: GatewayError, action: Action)
}

@MainActor
public protocol RunNotifying: AnyObject {
    func notifyFinished(_ execution: Execution, server: String)
}

extension GatewayError {
    /// Any error from a gateway, as one of ours.
    public static func from(_ error: any Error) -> GatewayError {
        if let known = error as? GatewayError { return known }
        return .unreachable(error.localizedDescription)
    }
}
