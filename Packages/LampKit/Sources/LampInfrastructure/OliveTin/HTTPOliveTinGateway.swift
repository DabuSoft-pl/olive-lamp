import Foundation
import LampApplication
import LampDomain

/// The OliveTin API over HTTP, with the server's credential on every request.
struct HTTPOliveTinGateway: OliveTinGateway {
    let client: ConnectClient

    func info() async throws -> ServerInfo {
        try await client.call("Init", Empty(), as: InitReply.self).info
    }

    func actions(dashboards: [String]) async throws -> [Action] {
        var seen = Set<String>()
        var all: [Action] = []
        let titles = dashboards.isEmpty ? [""] : dashboards
        for title in titles {
            let reply = try await client.call("GetDashboard", DashboardRequest(title: title), as: DashboardReply.self)
            for var action in reply.actions where seen.insert(action.id).inserted {
                // One dashboard: its fieldsets are the groups. Several: each dashboard is a group, its fieldsets sections.
                if titles.count > 1 {
                    let dashboard = reply.dashboard?.title.flatMap { $0.isEmpty ? nil : $0 } ?? title
                    // A fieldset named like its dashboard ("Actions" on "Actions") needs no heading of its own.
                    action.section = action.group == dashboard ? nil : action.group
                    action.group = dashboard
                }
                all.append(action)
            }
        }
        return all
    }

    func entityTypes() async throws -> [String] {
        try await client.call("GetEntities", EntitiesRequest(entityType: nil), as: EntitiesReply.self).types
    }

    func machines(entityType: String) async throws -> [Machine] {
        let reply = try await client.call("GetEntities", EntitiesRequest(entityType: entityType), as: EntitiesReply.self)
        let instances = (reply.entityDefinitions ?? [])
            .filter { ($0.title ?? entityType) == entityType }
            .flatMap { $0.instances ?? [] }
            .filter { !($0.uniqueKey ?? "").isEmpty }
        // The list may come without fields; then each entity is read on its own, as the web Lamp does.
        return try await withThrowingTaskGroup(of: (Int, Machine).self) { group in
            for (index, instance) in instances.enumerated() {
                group.addTask {
                    var message = instance
                    if (message.fields ?? [:]).isEmpty, let key = instance.uniqueKey {
                        if let full = try? await client.call("GetEntity", EntityRequest(type: entityType, uniqueKey: key), as: EntityMessage.self) {
                            message.fields = full.fields
                            message.title = message.title ?? full.title
                        }
                    }
                    let key = message.uniqueKey ?? String(index)
                    return (index, Machine(key: key, title: message.title ?? key, fields: message.fields ?? [:]))
                }
            }
            var machines: [(Int, Machine)] = []
            for try await item in group { machines.append(item) }
            return machines.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    func relatedActions(entityType: String, key: String) async throws -> [Action] {
        try await client.call("GetEntity", EntityRequest(type: entityType, uniqueKey: key), as: EntityMessage.self).actions
    }

    func start(actionID: String, arguments: [String: String], justification: String?) async throws -> String {
        let request = StartRequest(
            bindingId: actionID,
            arguments: arguments.sorted { $0.key < $1.key }.map { StartRequest.Argument(name: $0.key, value: $0.value) },
            justification: justification
        )
        let reply = try await client.call("StartAction", request, as: StartReply.self)
        guard let id = reply.executionTrackingId, !id.isEmpty else { throw GatewayError.refused("No execution id") }
        return id
    }

    func execution(id: String) async throws -> Execution {
        let reply = try await client.call("ExecutionStatus", TrackingRequest(executionTrackingId: id), as: StatusReply.self)
        guard let execution = reply.logEntry?.execution else { throw GatewayError.refused("Unknown execution") }
        return execution
    }

    func history() async throws -> [Execution] {
        let reply = try await client.call("GetLogs", LogsRequest(startOffset: 0), as: LogsReply.self)
        return (reply.logs ?? []).compactMap(\.execution).sorted {
            ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast)
        }
    }

    func stop(executionID: String) async throws {
        _ = try await client.call("KillAction", TrackingRequest(executionTrackingId: executionID), as: Empty.self)
    }

    func events() -> AsyncThrowingStream<ServerEvent, any Error> {
        let messages = client.stream("EventStream", Empty(), as: EventMessage.self)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await message in messages {
                        if let event = message.event { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Makes gateways on one shared session that keeps no cookies or cache of its own: every secret comes from the
/// credential store, request by request.
public struct HTTPGatewayFactory: GatewayMaking {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    public func gateway(address: URL, credential: Credential?) -> any OliveTinGateway {
        HTTPOliveTinGateway(client: ConnectClient(address: address, credential: credential, session: session))
    }
}
