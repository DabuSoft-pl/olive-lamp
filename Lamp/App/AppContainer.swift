import Foundation
import LampApplication
import LampDomain
import LampInfrastructure

/// Composition root: the one place that knows every layer. It builds the adapters, hands them to the use cases
/// through their ports and wires the use cases to the view models and controllers.
@MainActor
final class AppContainer {
    let preferences: Preferences
    let launchAtLogin = LaunchAtLogin()
    let panel = PanelViewModel()
    let panelActions: PanelController
    let servers: ServersController
    private let notifier = UserNotificationsAdapter()
    private(set) lazy var statusMenu = StatusItemMenu(panel: panel, actions: panelActions)
    private var timer: Timer?

    init(repository: any ServerRepository, credentials: any CredentialStore, gateways: any GatewayMaking, clock: any Clock, preferences: Preferences) {
        self.preferences = preferences
        let directory = ServerDirectory(repository: repository, credentials: credentials, gateways: gateways)
        let probe = ProbeServer(directory: directory)
        let runAction = RunAction(directory: directory, clock: clock, output: panel, notifier: notifier)
        panelActions = PanelController(
            model: panel,
            directory: directory,
            refreshOverview: RefreshOverview(directory: directory, clock: clock, output: panel),
            runAction: runAction,
            stopRun: StopRun(directory: directory, runs: runAction),
            chooseEntities: ChooseEntities(directory: directory),
            preferences: preferences
        )
        servers = ServersController(
            directory: directory, probe: probe, addServer: AddServer(directory: directory, probe: probe),
            signInAgain: SignInAgain(directory: directory, probe: probe), panel: panelActions
        )
    }

    static func live() -> AppContainer {
        AppContainer(
            repository: JSONServerRepository(directory: JSONServerRepository.defaultDirectory()),
            credentials: KeychainCredentialStore(),
            gateways: HTTPGatewayFactory(),
            clock: SystemClock(),
            preferences: Preferences()
        )
    }

    /// Reads the server now and every minute, so the menu bar mark stays current while the panel is closed.
    func start() {
        statusMenu.start()
        panelActions.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.panelActions.refresh() }
        }
    }
}
