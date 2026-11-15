import Foundation
import LampApplication
import LampDomain
import Observation

/// What the panel and the menu bar show. It implements the use cases' output ports.
@MainActor
@Observable
final class PanelViewModel: OverviewOutput, RunOutput {
    enum Content: Equatable {
        case loading
        case noServer
        case overview(Overview)
        case problem(GatewayError, Server)
    }

    /// What the menu bar mark says at a glance.
    enum BarState: Equatable {
        case quiet, running, failed, attention
    }

    private(set) var content: Content = .loading
    /// The last good overview, kept while a refresh fails so the panel does not go blank.
    private(set) var overview: Overview?
    private(set) var servers: [Server] = []
    private(set) var selectedServer: UUID?
    /// The run the panel follows: started here, or found running on the server.
    private(set) var run: RunProgress? {
        didSet {
            let output = run?.execution.output ?? ""
            if output != oldValue?.execution.output { logLines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }
        }
    }
    /// The followed run's log, split into lines once per change for the log view.
    private(set) var logLines: [String] = []
    private(set) var startProblem: String?
    /// A failure the user has not seen yet; opening the panel clears it.
    private(set) var unseenFailure = false
    var showingLog = false
    /// The user's choices: action id → argument name → value.
    var picks: [String: [String: String]] = [:]

    var history: [Execution] { overview?.history ?? [] }

    var barState: BarState {
        if let run, run.execution.isActive { return .running }
        if case .problem = content { return .attention }
        if unseenFailure { return .failed }
        if overview?.machines.contains(where: { $0.health == .failing }) == true { return .failed }
        if overview?.actions.contains(where: \.isRunning) == true { return .running }
        return .quiet
    }

    func setServers(_ servers: [Server], selected: UUID?) {
        self.servers = servers
        selectedServer = selected
    }

    func panelOpened() {
        unseenFailure = false
    }

    func dismissRun() {
        guard run?.execution.isActive != true else { return }
        run = nil
        showingLog = false
    }

    func clearStartProblem() {
        startProblem = nil
    }

    // MARK: OverviewOutput

    func show(_ overview: Overview) {
        self.overview = overview
        content = .overview(overview)
    }

    func showProblem(_ problem: GatewayError, server: Server) {
        content = .problem(problem, server)
    }

    func showNoServer() {
        overview = nil
        content = .noServer
    }

    // MARK: RunOutput

    func show(_ run: RunProgress) {
        let wasActive = self.run?.execution.isActive ?? false
        self.run = run
        startProblem = nil
        if wasActive, !run.execution.isActive, ![.succeeded, .stopped].contains(run.execution.state) { unseenFailure = true }
    }

    func showStartFailed(_ problem: GatewayError, action: Action) {
        startProblem = String(localized: "\(action.title) did not start: \(ProblemText.of(problem))")
    }
}

enum ProblemText {
    static func of(_ problem: GatewayError) -> String {
        switch problem {
        case .unreachable(let detail): String(localized: "Can't reach the server. \(detail)")
        case .signInNeeded: String(localized: "The server wants you to sign in again")
        case .notOliveTin: String(localized: "This address doesn't answer as OliveTin")
        case .refused(let message): message
        }
    }
}
