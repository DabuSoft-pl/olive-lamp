import AppKit
import LampApplication
import LampDomain

/// Turns what the user does in the panel into use cases.
@MainActor
final class PanelController {
    private let model: PanelViewModel
    private let directory: ServerDirectory
    private let refreshOverview: RefreshOverview
    private let runAction: RunAction
    private let stopRun: StopRun
    private let preferences: Preferences
    private var refreshing: Task<Void, Never>?
    private var following: Task<Void, Never>?

    init(
        model: PanelViewModel, directory: ServerDirectory, refreshOverview: RefreshOverview, runAction: RunAction,
        stopRun: StopRun, preferences: Preferences
    ) {
        self.model = model
        self.directory = directory
        self.refreshOverview = refreshOverview
        self.runAction = runAction
        self.stopRun = stopRun
        self.preferences = preferences
        syncServers()
    }

    func refresh() {
        guard refreshing == nil else { return }
        refreshing = Task {
            await refreshOverview()
            refreshing = nil
            followRunStartedElsewhere()
        }
    }

    func panelOpened() {
        model.panelOpened()
        refresh()
    }

    func select(_ server: Server) {
        guard server.id != model.selectedServer else { return }
        following?.cancel()
        following = nil
        model.dismissRun()
        directory.select(server.id)
        syncServers()
        refresh()
    }

    func syncServers() {
        model.setServers(directory.servers, selected: directory.selected?.id)
    }

    func run(_ action: Action) {
        switch action.launch {
        case .inBrowser:
            openInBrowser()
        case .direct, .pick:
            guard model.run?.execution.isActive != true else { return }
            let picked = model.picks[action.id] ?? [:]
            let reason = model.reasons[action.id] ?? action.justification
            model.clearStartProblem()
            following?.cancel()
            following = Task {
                await runAction(action, picked: picked, reason: reason, history: model.history, notify: preferences.notifyWhenDone)
                following = nil
                refresh()
            }
        }
    }

    func stop() {
        guard let execution = model.run?.execution, execution.isActive else { return }
        Task { try? await stopRun(execution) }
    }

    func openInBrowser() {
        guard let server = directory.selected else { return }
        NSWorkspace.shared.open(server.address)
    }

    func copyLog() {
        guard let output = model.run?.execution.output else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
    }

    /// A run started on the web page or by a schedule shows up in the panel too.
    private func followRunStartedElsewhere() {
        guard following == nil, model.run?.execution.isActive != true,
              let active = model.history.first(where: \.isActive) else { return }
        model.show(RunProgress(execution: active, estimate: RunEstimate(history: model.history, actionID: active.actionID)))
        following = Task {
            await runAction.follow(active, history: model.history)
            following = nil
            refresh()
        }
    }
}
