import Foundation
import LampDomain

/// Starts an action and follows it until it ends, then tells the user how it went.
@MainActor
public final class RunAction {
    private let directory: ServerDirectory
    private let clock: any Clock
    private weak var output: (any RunOutput)?
    private weak var notifier: (any RunNotifying)?
    /// How often a running execution is read again.
    public var pollInterval = 1.0
    /// Gives up following after this many failed reads in a row; the run itself goes on on the server.
    public var allowedMisses = 5
    /// Runs the user asked to stop, so their end reads as stopped, not failed.
    private var stopping: Set<String> = []
    /// The server each followed run lives on, so Stop reaches it even after the user selected another server.
    private var homes: [String: Server] = [:]

    public init(directory: ServerDirectory, clock: any Clock, output: any RunOutput, notifier: (any RunNotifying)?) {
        self.directory = directory
        self.clock = clock
        self.output = output
        self.notifier = notifier
    }

    /// Starts `action` with `picked`, the user's choice per list argument (the rest take their defaults), and `reason`
    /// when the action asks for one. `history` gives the estimate; `notify` sends a notification when the run ends.
    public func callAsFunction(_ action: Action, picked: [String: String] = [:], reason: String? = nil, history: [Execution], notify: Bool) async {
        guard let server = directory.selected else { return }
        let gateway = directory.gateway(for: server)
        let id: String
        do {
            let justification = action.justification == nil ? nil : reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            id = try await gateway.start(actionID: action.id, arguments: action.startArguments(picked: picked), justification: justification)
        } catch {
            output?.showStartFailed(GatewayError.from(error), action: action)
            return
        }
        homes[id] = server
        let estimate = RunEstimate(history: history, actionID: action.id)
        var last = Execution(id: id, actionID: action.id, actionTitle: action.title, startedAt: clock.now)
        output?.show(RunProgress(execution: last, estimate: estimate))
        await follow(id: id, last: &last, estimate: estimate, gateway: gateway)
        if notify, last.deservesNotice() { notifier?.notifyFinished(last, server: server.name) }
    }

    /// Follows a run started elsewhere (the web page, a schedule) until it ends.
    public func follow(_ execution: Execution, history: [Execution]) async {
        guard let server = directory.selected else { return }
        homes[execution.id] = server
        var last = execution
        await follow(id: execution.id, last: &last, estimate: RunEstimate(history: history, actionID: execution.actionID), gateway: directory.gateway(for: server))
    }

    private func follow(id: String, last: inout Execution, estimate: RunEstimate?, gateway: any OliveTinGateway) async {
        var misses = 0
        while !last.isFinished, misses < allowedMisses {
            do {
                try await clock.sleep(seconds: pollInterval)
            } catch {
                return  // cancelled
            }
            do {
                var read = try await gateway.execution(id: id)
                if read.startedAt == nil { read.startedAt = last.startedAt }
                read.stoppedByUser = stopping.contains(id)
                last = read
                misses = 0
                output?.show(RunProgress(execution: last, estimate: estimate))
            } catch {
                misses += 1
            }
        }
    }

    func markStopping(_ id: String) {
        stopping.insert(id)
    }

    /// The server a run Lamp follows was started on or found on.
    public func server(of id: String) -> Server? {
        homes[id]
    }
}

/// Stops a running execution. The run it follows then ends as stopped, without a failure dot or notification.
@MainActor
public final class StopRun {
    private let directory: ServerDirectory
    private let runs: RunAction

    public init(directory: ServerDirectory, runs: RunAction) {
        self.directory = directory
        self.runs = runs
    }

    public func callAsFunction(_ execution: Execution) async throws(GatewayError) {
        guard let server = runs.server(of: execution.id) ?? directory.selected else { return }
        runs.markStopping(execution.id)
        do {
            try await directory.gateway(for: server).stop(executionID: execution.id)
        } catch {
            throw GatewayError.from(error)
        }
    }
}
