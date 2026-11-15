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

    public init(directory: ServerDirectory, clock: any Clock, output: any RunOutput, notifier: (any RunNotifying)?) {
        self.directory = directory
        self.clock = clock
        self.output = output
        self.notifier = notifier
    }

    /// Starts `action` with `picked` for its one choice argument, if it has one.
    /// `history` gives the estimate; `notify` sends a notification when the run ends.
    public func callAsFunction(_ action: Action, picked: String? = nil, history: [Execution], notify: Bool) async {
        guard let server = directory.selected else { return }
        let gateway = directory.gateway(for: server)
        let id: String
        do {
            id = try await gateway.start(actionID: action.id, arguments: action.startArguments(picked: picked))
        } catch {
            output?.showStartFailed(GatewayError.from(error), action: action)
            return
        }
        let estimate = RunEstimate(history: history, actionID: action.id)
        var last = Execution(id: id, actionID: action.id, actionTitle: action.title, startedAt: clock.now)
        output?.show(RunProgress(execution: last, estimate: estimate))
        await follow(id: id, last: &last, estimate: estimate, gateway: gateway)
        if notify, last.isFinished { notifier?.notifyFinished(last, server: server.name) }
    }

    /// Follows a run started elsewhere (the web page, a schedule) until it ends.
    public func follow(_ execution: Execution, history: [Execution]) async {
        guard let server = directory.selected else { return }
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
                last = read
                misses = 0
                output?.show(RunProgress(execution: last, estimate: estimate))
            } catch {
                misses += 1
            }
        }
    }
}

/// Stops a running execution.
@MainActor
public final class StopRun {
    private let directory: ServerDirectory

    public init(directory: ServerDirectory) {
        self.directory = directory
    }

    public func callAsFunction(_ execution: Execution) async throws(GatewayError) {
        guard let server = directory.selected else { return }
        do {
            try await directory.gateway(for: server).stop(executionID: execution.id)
        } catch {
            throw GatewayError.from(error)
        }
    }
}
