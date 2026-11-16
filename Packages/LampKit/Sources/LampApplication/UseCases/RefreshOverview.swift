import Foundation
import LampDomain

/// Reads the selected server: who you are, its actions, its machines and the latest runs.
@MainActor
public final class RefreshOverview {
    private let directory: ServerDirectory
    private let clock: any Clock
    private weak var output: (any OverviewOutput)?
    private let catalog: (any ActionCatalog)?

    public init(directory: ServerDirectory, clock: any Clock, output: any OverviewOutput, catalog: (any ActionCatalog)? = nil) {
        self.directory = directory
        self.clock = clock
        self.output = output
        self.catalog = catalog
    }

    /// What it read is dropped when the user selected another server meanwhile, or the refresh was cancelled.
    public func callAsFunction() async {
        guard let server = directory.selected else {
            output?.showNoServer()
            return
        }
        let gateway = directory.gateway(for: server)
        do {
            let info = try await gateway.info()
            if info.loginRequired, !info.isSignedIn { throw GatewayError.signInNeeded }
            async let actions = gateway.actions(dashboards: info.rootDashboards)
            async let entities = Self.entities(of: server, from: gateway)
            async let history = gateway.history()
            // A server without entities, or with an older API, still shows its actions.
            let (types, type, machines) = await entities
            let overview = Overview(
                server: server,
                info: info,
                actions: try await actions,
                machines: machines,
                entityTypes: types,
                entityType: type,
                history: (try? await history) ?? [],
                checkedAt: clock.now
            )
            guard isCurrent(server) else { return }
            output?.show(overview)
            try? catalog?.publish(overview)
        } catch {
            guard isCurrent(server) else { return }
            output?.showProblem(GatewayError.from(error), server: server)
        }
    }

    private func isCurrent(_ server: Server) -> Bool {
        !Task.isCancelled && directory.selected?.id == server.id
    }

    private nonisolated static func entities(
        of server: Server, from gateway: any OliveTinGateway
    ) async -> (types: [String], type: String?, machines: [Machine]) {
        let types = (try? await gateway.entityTypes()) ?? []
        guard let type = server.entityType(among: types) else { return (types, nil, []) }
        return (types, type, (try? await gateway.machines(entityType: type)) ?? [])
    }
}
