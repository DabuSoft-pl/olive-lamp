import Foundation
import Testing
@testable import LampApplication
import LampDomain

final class FakeGateway: OliveTinGateway, @unchecked Sendable {
    var serverInfo = ServerInfo(title: "Homelab", version: "3000.22.0", user: "damian", loginRequired: false, offersLocalLogin: false, oAuthProviders: [], rootDashboards: ["Homelab"])
    var infoError: GatewayError?
    var actionList: [Action] = [Action(id: "check", title: "Check")]
    var machineError: GatewayError?
    var types = ["container", "machine"]
    /// The entity type of every `machines(entityType:)` call.
    var listed: [String] = []
    var startError: GatewayError?
    /// Successive answers to `execution(id:)`; the last one repeats.
    var reads: [Execution] = []
    var started: [(String, [String: String])] = []
    var reasons: [String?] = []
    var stopped: [String] = []
    private var readIndex = 0

    func info() async throws -> ServerInfo {
        if let infoError { throw infoError }
        return serverInfo
    }

    func actions(dashboards: [String]) async throws -> [Action] { actionList }

    func entityTypes() async throws -> [String] { types }

    var related: [Action]?

    func relatedActions(entityType: String, key: String) async throws -> [Action] {
        related ?? [Action(id: "start-\(key)", title: "Start \(key)"), Action(id: "hidden", title: "Hidden", canRun: false)]
    }

    func machines(entityType: String) async throws -> [Machine] {
        listed.append(entityType)
        if let machineError { throw machineError }
        return [Machine(id: "0", name: "pve", health: .ok)]
    }

    func start(actionID: String, arguments: [String: String], justification: String?) async throws -> String {
        if let startError { throw startError }
        started.append((actionID, arguments))
        reasons.append(justification)
        return "run-1"
    }

    func execution(id: String) async throws -> Execution {
        let read = reads[min(readIndex, reads.count - 1)]
        readIndex += 1
        return read
    }

    func history() async throws -> [Execution] { [] }

    func stop(executionID: String) async throws { stopped.append(executionID) }
}

final class FakeGateways: GatewayMaking, @unchecked Sendable {
    let gateway: FakeGateway
    /// Every address a gateway was made for, in order.
    var addresses: [URL] = []
    init(gateway: FakeGateway) { self.gateway = gateway }
    func gateway(address: URL, credential: Credential?) -> any OliveTinGateway {
        addresses.append(address)
        return gateway
    }
}

final class MemoryServers: ServerRepository, @unchecked Sendable {
    var servers: [Server] = []
    func load() throws -> [Server] { servers }
    func save(_ servers: [Server]) throws { self.servers = servers }
}

final class MemoryCredentials: CredentialStore, @unchecked Sendable {
    var items: [UUID: Credential] = [:]
    func credential(for server: UUID) throws -> Credential? { items[server] }
    func store(_ credential: Credential, for server: UUID) throws { items[server] = credential }
    func remove(for server: UUID) throws { items[server] = nil }
}

struct InstantClock: Clock {
    var now: Date { Date(timeIntervalSince1970: 10_000) }
    func sleep(seconds: Double) async throws {}
}

@MainActor
final class Recorder: OverviewOutput, RunOutput, RunNotifying {
    var overviews: [Overview] = []
    var problems: [GatewayError] = []
    var noServer = false
    var runs: [RunProgress] = []
    var startFailures: [GatewayError] = []
    var notified: [Execution] = []

    func show(_ overview: Overview) { overviews.append(overview) }
    func showProblem(_ problem: GatewayError, server: Server) { problems.append(problem) }
    func showNoServer() { noServer = true }
    func show(_ run: RunProgress) { runs.append(run) }
    func showStartFailed(_ problem: GatewayError, action: Action) { startFailures.append(problem) }
    func notifyFinished(_ execution: Execution, server: String) { notified.append(execution) }
}

@MainActor
@Suite struct UseCaseTests {
    let gateway = FakeGateway()
    let servers = MemoryServers()
    let credentials = MemoryCredentials()
    let recorder = Recorder()

    func directory(withServer: Bool = true) -> ServerDirectory {
        if withServer {
            servers.servers = [Server(name: "Homelab", address: URL(string: "https://panel.example.ts.net")!, signIn: .automatic)]
        }
        return ServerDirectory(repository: servers, credentials: credentials, gateways: FakeGateways(gateway: gateway))
    }

    func running(_ output: String = "") -> Execution {
        Execution(id: "run-1", actionID: "update", actionTitle: "Update", startedAt: Date(timeIntervalSince1970: 9_990), output: output)
    }

    @Test func runFollowsUntilFinishedAndNotifies() async {
        var done = running("ok: [nas]")
        done.isFinished = true
        done.finishedAt = Date(timeIntervalSince1970: 10_030)  // 40 s: long enough to be worth a notification
        gateway.reads = [running("TASK [apt]"), done]
        let action = Action(id: "update", title: "Update", arguments: [ActionArgument(name: "confirm", title: "OK", kind: .confirmation)])
        let run = RunAction(directory: directory(), clock: InstantClock(), output: recorder, notifier: recorder)

        await run(action, history: [], notify: true)

        #expect(gateway.started.first?.1 == ["confirm": "1"])
        #expect(recorder.runs.map(\.execution.state) == [.running, .running, .succeeded])
        #expect(recorder.notified.map(\.id) == ["run-1"])
    }

    @Test func aRunTheUserStoppedEndsStoppedWithoutANotification() async throws {
        let directory = directory()
        let run = RunAction(directory: directory, clock: InstantClock(), output: recorder, notifier: recorder)
        var killed = running()
        killed.isFinished = true
        killed.exitCode = -1
        gateway.reads = [running(), killed]
        try await StopRun(directory: directory, runs: run)(running())
        await run(Action(id: "update", title: "Update"), history: [], notify: true)

        #expect(gateway.stopped == ["run-1"])
        #expect(recorder.runs.last?.execution.state == .stopped)
        #expect(recorder.notified.isEmpty)
    }

    @Test func stopReachesTheRunsOwnServerAfterASwitch() async throws {
        let gateways = FakeGateways(gateway: gateway)
        let home = Server(name: "Homelab", address: URL(string: "https://panel.example.ts.net")!, signIn: .automatic)
        let other = Server(name: "Office", address: URL(string: "https://office.example.com")!, signIn: .automatic)
        servers.servers = [home, other]
        let directory = ServerDirectory(repository: servers, credentials: credentials, gateways: gateways)
        directory.select(home.id)
        let run = RunAction(directory: directory, clock: InstantClock(), output: recorder, notifier: nil)
        var done = running()
        done.isFinished = true
        gateway.reads = [done]
        await run.follow(running(), history: [])
        directory.select(other.id)
        gateways.addresses = []

        try await StopRun(directory: directory, runs: run)(running())

        #expect(gateways.addresses == [home.address])
        #expect(gateway.stopped == ["run-1"])
    }

    @Test func aReasonGoesOnlyWithAnActionThatAsksForOne() async {
        var done = running()
        done.isFinished = true
        gateway.reads = [done]
        let run = RunAction(directory: directory(), clock: InstantClock(), output: recorder, notifier: nil)
        await run(Action(id: "prune", title: "Prune", justification: ""), reason: "  disk full \n", history: [], notify: false)
        await run(Action(id: "check", title: "Check"), reason: "ignored", history: [], notify: false)
        #expect(gateway.reasons == ["disk full", nil])
    }

    @Test func noNotificationWhenNotAsked() async {
        var done = running()
        done.isFinished = true
        gateway.reads = [done]
        await RunAction(directory: directory(), clock: InstantClock(), output: recorder, notifier: recorder)(Action(id: "update", title: "Update"), history: [], notify: false)
        #expect(recorder.notified.isEmpty)
    }

    @Test func refusedStartIsShown() async {
        gateway.startError = .refused("confirmation required")
        await RunAction(directory: directory(), clock: InstantClock(), output: recorder, notifier: recorder)(Action(id: "update", title: "Update"), history: [], notify: true)
        #expect(recorder.startFailures == [.refused("confirmation required")])
        #expect(recorder.runs.isEmpty)
    }

    @Test func overviewSurvivesMissingMachines() async {
        gateway.machineError = .refused("no entities")
        await RefreshOverview(directory: directory(), clock: InstantClock(), output: recorder)()
        #expect(recorder.overviews.first?.actions.map(\.id) == ["check"])
        #expect(recorder.overviews.first?.machines.isEmpty == true)
    }

    @Test func machinesComeFirstThenAnyType() async {
        await RefreshOverview(directory: directory(), clock: InstantClock(), output: recorder)()
        #expect(gateway.listed == ["machine"])
        #expect(recorder.overviews.first?.entityTypes == ["container", "machine"])
        gateway.types = ["container"]
        await RefreshOverview(directory: directory(), clock: InstantClock(), output: recorder)()
        #expect(gateway.listed == ["machine", "container"])
        #expect(recorder.overviews.last?.entityType == "container")
    }

    @Test func chosenAndHiddenEntitiesAreKept() async throws {
        let directory = directory()
        let refresh = RefreshOverview(directory: directory, clock: InstantClock(), output: recorder)
        try ChooseEntities(directory: directory)("container")
        #expect(servers.servers.first?.entityType == "container")
        await refresh()
        #expect(gateway.listed == ["container"])
        try ChooseEntities(directory: directory)("")
        await refresh()
        #expect(gateway.listed == ["container"])
        #expect(recorder.overviews.last?.machines.isEmpty == true)
        #expect(recorder.overviews.last?.entityType == nil)
    }

    @Test func machineActionsAreTheRunnableOnes() async throws {
        let actions = try await LoadMachineActions(directory: directory())(Machine(id: "nas", name: "nas"), entityType: "machine")
        #expect(actions.map(\.id) == ["start-nas"])
    }

    @Test func withoutBoundActionsTheListsThatOfferTheMachineStandIn() async throws {
        let host = ActionArgument(name: "limit", title: "Machine", kind: .choice(["all", "pve"].map { .init(value: $0, title: $0) }))
        let offered = [Action(id: "update", title: "Update", arguments: [host]), Action(id: "wake", title: "Wake")]
        gateway.related = []
        let actions = try await LoadMachineActions(directory: directory())(
            Machine(id: "0", name: "pve"), entityType: "machine", offered: offered
        )
        #expect(actions.map(\.id) == ["update"])
        #expect(actions.first?.startArguments() == ["limit": "pve"])
    }

    @Test func guestOnALockedServerMustSignIn() async {
        gateway.serverInfo.user = ""
        gateway.serverInfo.loginRequired = true
        await RefreshOverview(directory: directory(), clock: InstantClock(), output: recorder)()
        #expect(recorder.problems == [.signInNeeded])
    }

    @Test func noServerYet() async {
        await RefreshOverview(directory: directory(withServer: false), clock: InstantClock(), output: recorder)()
        #expect(recorder.noServer)
    }

    @Test func addServerKeepsTheSecretOutOfTheServerList() async throws {
        let directory = directory(withServer: false)
        let add = AddServer(directory: directory, probe: ProbeServer(directory: directory))
        let server = try await add(name: " ", address: URL(string: "https://ops.example.com")!, signIn: .apiKey, credential: .apiKey("secret"))

        #expect(server.name == "Homelab")
        #expect(servers.servers == [server])
        #expect(credentials.items[server.id] == .apiKey("secret"))
    }

    @Test func addServerRefusesAGuestWhereLoginIsRequired() async {
        gateway.serverInfo.user = ""
        gateway.serverInfo.loginRequired = true
        let directory = directory(withServer: false)
        let add = AddServer(directory: directory, probe: ProbeServer(directory: directory))
        await #expect(throws: GatewayError.signInNeeded) {
            _ = try await add(name: "x", address: URL(string: "https://ops.example.com")!, signIn: .automatic, credential: nil)
        }
        #expect(servers.servers.isEmpty)
    }

    @Test func fallbackNameUsesTheHostForPlainOliveTin() {
        let info = ServerInfo(title: "OliveTin", version: "", user: "", loginRequired: false, offersLocalLogin: false, oAuthProviders: [], rootDashboards: [])
        #expect(AddServer.fallbackName(info: info, address: URL(string: "https://ops.example.com:1337")!) == "ops.example.com")
    }

    @Test func signingInAgainKeepsTheNewSession() async throws {
        let directory = directory()
        let server = try #require(directory.selected)
        try await SignInAgain(directory: directory, probe: ProbeServer(directory: directory))(server, credential: .cookies(["olivetin-sid-local": "new"]))
        #expect(credentials.items[server.id] == .cookies(["olivetin-sid-local": "new"]))
    }

    @Test func signingInAgainAsAGuestKeepsNothing() async throws {
        gateway.serverInfo.user = "guest"
        gateway.serverInfo.loginRequired = true
        let directory = directory()
        let server = try #require(directory.selected)
        await #expect(throws: GatewayError.signInNeeded) {
            try await SignInAgain(directory: directory, probe: ProbeServer(directory: directory))(server, credential: .cookies(["a": "b"]))
        }
        #expect(credentials.items[server.id] == nil)
    }

    @Test func removingAServerDropsItsSecret() throws {
        let directory = directory()
        let id = try #require(directory.selected?.id)
        credentials.items[id] = .apiKey("k")
        try directory.remove(id)
        #expect(credentials.items[id] == nil)
        #expect(directory.selected == nil)
    }
}

@Suite struct SessionCookiesTests {
    func cookie(_ name: String, domain: String, expires: Date? = nil, secure: Bool = false) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: "v-\(name)", .domain: domain, .path: "/"]
        if let expires { properties[.expires] = expires }
        if secure { properties[.secure] = "TRUE" }
        return HTTPCookie(properties: properties)!
    }

    @Test func keepsOnlyWhatTheServerWouldGet() {
        let cookies = [
            cookie("olivetin-sid-local", domain: "panel.example.com"),
            cookie("authelia_session", domain: ".example.com"),
            cookie("user_session", domain: "github.com"),
            cookie("old", domain: "panel.example.com", expires: .distantPast),
        ]
        let credential = SessionCookies.credential(from: cookies, for: URL(string: "https://panel.example.com/")!)
        #expect(credential == .cookies(["olivetin-sid-local": "v-olivetin-sid-local", "authelia_session": "v-authelia_session"]))
    }

    @Test func aSecureCookieNeverGoesOverPlainHTTP() {
        let cookies = [cookie("sid", domain: "olivetin.local", secure: true), cookie("plain", domain: "olivetin.local")]
        #expect(SessionCookies.credential(from: cookies, for: URL(string: "http://olivetin.local:1337")!) == .cookies(["plain": "v-plain"]))
        #expect(SessionCookies.credential(from: cookies, for: URL(string: "https://olivetin.local")!) == .cookies(["sid": "v-sid", "plain": "v-plain"]))
    }

    @Test func noCookiesNoCredential() {
        #expect(SessionCookies.credential(from: [cookie("a", domain: "other.org")], for: URL(string: "https://panel.example.com")!) == nil)
    }
}

@Suite struct RunRequestTests {
    let hosts = ActionArgument(name: "limit", title: "Machine", kind: .choice([.init(value: "nas", title: "nas"), .init(value: "all", title: "All")]))
    let confirm = ActionArgument(name: "confirm", title: "Sure?", kind: .confirmation)

    func request(_ query: String) -> RunRequest? {
        RunRequest(url: URL(string: "olivelamp://run?\(query)")!)
    }

    @Test func readsALink() throws {
        let server = UUID()
        let link = try #require(request("token=abc&server=\(server.uuidString)&action=update&confirmed=1&reason=patch%20day&arg.limit=nas"))
        #expect(link == RunRequest(token: "abc", server: server, actionID: "update", confirmed: true, reason: "patch day", arguments: ["limit": "nas"]))
        #expect(request("action=update") == nil)
        #expect(RunRequest(url: URL(string: "https://example.com/run?token=a&action=b")!) == nil)
    }

    @Test func tokenMustMatch() throws {
        let link = try #require(request("token=abc&action=a"))
        #expect(throws: Never.self) { try link.check(token: "abc") }
        #expect(throws: RunRequest.Problem.wrongToken) { try link.check(token: "abd") }
        #expect(throws: RunRequest.Problem.wrongToken) { try link.check(token: "abcd") }
        #expect(throws: RunRequest.Problem.wrongToken) { try link.check(token: "") }
    }

    @Test func holdWantsConfirmationAndChoicesMustBeOffered() throws {
        let update = Action(id: "update", title: "Update", arguments: [hosts, confirm])
        #expect(throws: RunRequest.Problem.needsConfirmation) { try request("token=t&action=update&arg.limit=nas")!.picks(for: update) }
        #expect(try request("token=t&action=update&confirmed=1&arg.limit=nas")!.picks(for: update) == ["limit": "nas"])
        #expect(try request("token=t&action=update&confirmed=1")!.picks(for: update) == [:])
        #expect(throws: RunRequest.Problem.notAChoice("Machine")) {
            try request("token=t&action=update&confirmed=1&arg.limit=everything")!.picks(for: update)
        }
        let text = Action(id: "say", title: "Say", arguments: [ActionArgument(name: "text", title: "Text", kind: .other("ascii"))])
        #expect(throws: RunRequest.Problem.needsBrowser) { try request("token=t&action=say")!.picks(for: text) }
        #expect(throws: RunRequest.Problem.cannotRun) { try request("token=t&action=x")!.picks(for: Action(id: "x", title: "X", canRun: false)) }
    }
}
