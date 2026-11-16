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
    private let chooseEntities: ChooseEntities
    private let loadMachineActions: LoadMachineActions
    private let preferences: Preferences
    /// The token `olivelamp://run` links must carry; nil turns links off.
    private let linkToken: String?
    private var refreshing: Task<Void, Never>?
    private var following: Task<Void, Never>?

    init(
        model: PanelViewModel, directory: ServerDirectory, refreshOverview: RefreshOverview, runAction: RunAction,
        stopRun: StopRun, chooseEntities: ChooseEntities, loadMachineActions: LoadMachineActions,
        preferences: Preferences,
        linkToken: String? = nil
    ) {
        self.linkToken = linkToken
        self.model = model
        self.directory = directory
        self.refreshOverview = refreshOverview
        self.runAction = runAction
        self.stopRun = stopRun
        self.chooseEntities = chooseEntities
        self.loadMachineActions = loadMachineActions
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

    /// `type` is an entity type to list, or "" to list none.
    func showEntities(_ type: String) {
        try? chooseEntities(type)
        refreshing?.cancel()
        refreshing = nil
        refresh()
    }

    /// The actions OliveTin binds to one machine, else the panel's actions set to it; nil when the server could not be
    /// read.
    func actions(of machine: Machine) async -> [Action]? {
        guard let type = model.overview?.entityType else { return [] }
        return try? await loadMachineActions(machine, entityType: type, offered: model.overview?.actions ?? [])
    }

    /// Runs an action from an `olivelamp://run` link, on a fresh read of its server, by the same rules as the panel.
    func open(_ url: URL) {
        guard let linkToken, let request = RunRequest(url: url) else { return }
        do throws(RunRequest.Problem) {
            try request.check(token: linkToken)
        } catch {
            return
        }
        if let id = request.server, id != model.selectedServer, let server = directory.servers.first(where: { $0.id == id }) {
            select(server)
        }
        Task {
            refreshing?.cancel()
            refreshing = nil
            await refreshOverview()
            guard request.server == nil || request.server == model.selectedServer else { return }
            guard let action = model.overview?.actions.first(where: { $0.id == request.actionID }) else {
                model.showLinkProblem(String(localized: "Olive Lamp found no action \(request.actionID) on this server"))
                return
            }
            do throws(RunRequest.Problem) {
                let picks = try request.picks(for: action)
                if !picks.isEmpty { model.picks[action.id, default: [:]].merge(picks) { $1 } }
                if let reason = request.reason { model.reasons[action.id] = reason }
                run(action)
            } catch {
                model.showLinkProblem(Self.text(of: error, action: action))
            }
        }
    }

    private static func text(of problem: RunRequest.Problem, action: Action) -> String {
        switch problem {
        case .wrongToken, .unknownAction: String(localized: "Olive Lamp found no action \(action.title) on this server")
        case .cannotRun: String(localized: "You may not run \(action.title)")
        case .needsConfirmation: String(localized: "\(action.title) runs only after you confirm it")
        case .needsBrowser: String(localized: "\(action.title) runs from the web page")
        case .notAChoice(let argument): String(localized: "\(action.title) does not offer that \(argument)")
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
