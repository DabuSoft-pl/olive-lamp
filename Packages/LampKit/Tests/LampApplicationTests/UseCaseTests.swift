import Foundation
import Testing
@testable import LampApplication
import LampDomain

final class FakeGateway: OliveTinGateway, @unchecked Sendable {
    var serverInfo = ServerInfo(title: "Homelab", version: "3000.22.0", user: "damian", loginRequired: false, offersLocalLogin: false, oAuthProviders: [], rootDashboards: ["Homelab"])
    var infoError: GatewayError?
    var actionList: [Action] = [Action(id: "check", title: "Check")]
    var machineError: GatewayError?
    var startError: GatewayError?
    /// Successive answers to `execution(id:)`; the last one repeats.
    var reads: [Execution] = []
    var started: [(String, [String: String])] = []
    var stopped: [String] = []
    private var readIndex = 0

    func info() async throws -> ServerInfo {
        if let infoError { throw infoError }
        return serverInfo
    }

    func actions(dashboards: [String]) async throws -> [Action] { actionList }

    func machines(entityType: String) async throws -> [Machine] {
        if let machineError { throw machineError }
        return [Machine(id: "0", name: "pve", health: .ok)]
    }

    func start(actionID: String, arguments: [String: String]) async throws -> String {
        if let startError { throw startError }
        started.append((actionID, arguments))
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

struct FakeGateways: GatewayMaking {
    let gateway: FakeGateway
    func gateway(address: URL, credential: Credential?) -> any OliveTinGateway { gateway }
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
        gateway.reads = [running("TASK [apt]"), done]
        let action = Action(id: "update", title: "Update", arguments: [ActionArgument(name: "confirm", title: "OK", kind: .confirmation)])
        let run = RunAction(directory: directory(), clock: InstantClock(), output: recorder, notifier: recorder)

        await run(action, history: [], notify: true)

        #expect(gateway.started.first?.1 == ["confirm": "1"])
        #expect(recorder.runs.map(\.execution.state) == [.running, .running, .succeeded])
        #expect(recorder.notified.map(\.id) == ["run-1"])
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

    @Test func removingAServerDropsItsSecret() throws {
        let directory = directory()
        let id = try #require(directory.selected?.id)
        credentials.items[id] = .apiKey("k")
        try directory.remove(id)
        #expect(credentials.items[id] == nil)
        #expect(directory.selected == nil)
    }
}
