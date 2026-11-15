import Foundation
import LampDomain

/// Reads the selected server: who you are, its actions, its machines and the latest runs.
@MainActor
public final class RefreshOverview {
    private let directory: ServerDirectory
    private let clock: any Clock
    private weak var output: (any OverviewOutput)?
    /// The entity type the web Lamp's status playbook fills.
    public var machineEntityType = "machine"

    public init(directory: ServerDirectory, clock: any Clock, output: any OverviewOutput) {
        self.directory = directory
        self.clock = clock
        self.output = output
    }

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
            async let machines = gateway.machines(entityType: machineEntityType)
            async let history = gateway.history()
            // A server without machines, or with an older API, still shows its actions.
            let overview = Overview(
                server: server,
                info: info,
                actions: try await actions,
                machines: (try? await machines) ?? [],
                history: (try? await history) ?? [],
                checkedAt: clock.now
            )
            output?.show(overview)
        } catch {
            output?.showProblem(GatewayError.from(error), server: server)
        }
    }
}
