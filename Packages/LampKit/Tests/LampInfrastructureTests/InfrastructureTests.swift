import Foundation
import Testing
import LampApplication
import LampDomain
@testable import LampInfrastructure

@Suite struct StockOliveTinTests {
    /// GetEntities {} on OliveTin 3000.22 with its Docker sample: list entries come without fields.
    @Test func entityTypesWithEntitiesOnly() throws {
        let json = """
        {"entityDefinitions":[{"title":"container","instances":[{"title":"6c1f","uniqueKey":"6c1f"}]},
          {"title":"server","instances":[]},{"title":"container","instances":[{"uniqueKey":"x"}]}]}
        """
        #expect(try JSONDecoder().decode(EntitiesReply.self, from: Data(json.utf8)).types == ["container"])
        #expect(String(decoding: try JSONEncoder().encode(EntitiesRequest(entityType: nil)), as: UTF8.self) == "{}")
    }

    /// "Delete old backups" from OliveTin 3000.22's own sample config.
    @Test func reasonUnnamedConfirmationAndHTMLFromTheSampleConfig() throws {
        let json = """
        {"dashboard":{"title":"Actions","contents":[{"type":"fieldset","title":"Actions","contents":[
          {"type":"link","action":{"bindingId":"del","title":"Delete old backups","canExec":true,"justification":" ","arguments":[
            {"name":"","title":"Description","type":"html","defaultValue":"See <a href=x>x</a>"},
            {"name":"","title":"Are you sure?!","type":"confirmation"}]}},
          {"type":"link","action":{"bindingId":"ping","title":"Ping","canExec":true,"justification":""}},
          {"type":"link","action":{"bindingId":"dirs","title":"Backup","canExec":true,"arguments":[
            {"name":"directories","type":"checklist","choices":[{"value":"Documents"},{"value":"Pictures"}]}]}}
        ]}]}}
        """
        let actions = try JSONDecoder().decode(DashboardReply.self, from: Data(json.utf8)).actions
        #expect(actions[0].justification == "")
        #expect(actions[0].requiresHold)
        #expect(actions[0].launch == .direct)
        #expect(actions[0].startArguments() == ["": "1"])
        #expect(actions[1].justification == nil)
        #expect(actions[2].launch == .inBrowser)
    }
}

@Suite struct WireTests {
    @Test func dashboardActionsKeepTheirTopLevelGroup() throws {
        let json = """
        {"dashboard":{"title":"Homelab","contents":[
          {"type":"fieldset","title":"Everyday","contents":[{"type":"fieldset","title":"Actions","contents":[
            {"type":"link","title":"Check","action":{"bindingId":"check","title":"Check machines","canExec":true,
              "arguments":[{"name":"limit","title":"Machine","type":"ascii_identifier","choices":[{"value":"nas","title":"nas"}]}]}},
            {"type":"link","title":"Prune","action":{"bindingId":"prune","title":"Docker cleanup","canExec":true,"hasRunningInstance":true,
              "arguments":[{"name":"confirm","title":"I understand","type":"confirmation"}]}}]}]},
          {"type":"link","action":{"bindingId":"loose","title":"Loose"}},
          {"type":"link","action":{"title":"No id"}}
        ]}}
        """
        let actions = try JSONDecoder().decode(DashboardReply.self, from: Data(json.utf8)).actions
        #expect(actions.map(\.id) == ["check", "prune", "loose"])
        #expect(actions.map(\.group) == ["Everyday", "Everyday", nil])
        #expect(actions[0].launch == .pick([ActionArgument(name: "limit", title: "Machine", kind: .choice([.init(value: "nas", title: "nas")]))]))
        #expect(actions[1].requiresHold)
        #expect(actions[1].isRunning)
        #expect(!actions[2].canRun)
    }

    @Test func emptyFieldsTakeTheirDefaults() throws {
        let info = try JSONDecoder().decode(InitReply.self, from: Data("{}".utf8)).info
        #expect(info.user == "")
        #expect(!info.loginRequired)
        #expect(info.rootDashboards.isEmpty)
    }

    @Test func logEntryBecomesAnExecution() throws {
        let json = """
        {"logEntry":{"executionTrackingId":"run-7","bindingId":"update","actionTitle":"Update","user":"damian",
         "datetimeStarted":"2026-11-15 18:08:00","datetimeFinished":"0001-01-01 00:00:00","output":"TASK [apt]","canKill":true}}
        """
        let execution = try #require(try JSONDecoder().decode(StatusReply.self, from: Data(json.utf8)).logEntry?.execution)
        #expect(execution.state == .running)
        #expect(execution.finishedAt == nil)
        #expect(execution.startedAt != nil)
        #expect(execution.canKill)
    }

    @Test func oliveTinTimeIsLocalWallClock() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        #expect(OliveTinTime.parse("2026-11-15 18:08:05", timeZone: utc) == Date(timeIntervalSince1970: 1_794_766_085))
        #expect(OliveTinTime.parse("0001-01-01 00:00:00") == nil)
        #expect(OliveTinTime.parse("") == nil)
        #expect(OliveTinTime.parse("2026-11-15T18:08:05Z") == Date(timeIntervalSince1970: 1_794_766_085))
    }
}

@Suite struct ConnectClientTests {
    func client(_ credential: Credential?, address: String = "https://panel.example.ts.net") -> ConnectClient {
        ConnectClient(address: URL(string: address)!, credential: credential, session: .shared)
    }

    @Test func endpointKeepsAPathPrefix() {
        #expect(ConnectClient.endpoint(address: URL(string: "https://example.com/olivetin")!, method: "Init").absoluteString
            == "https://example.com/olivetin/api/olivetin.api.v1.OliveTinApiService/Init")
        #expect(ConnectClient.endpoint(address: URL(string: "http://10.0.0.5:1337/")!, method: "Init").absoluteString
            == "http://10.0.0.5:1337/api/olivetin.api.v1.OliveTinApiService/Init")
    }

    @Test func credentialsBecomeHeaders() {
        #expect(client(.apiKey("k1")).makeRequest(method: "Init", body: Empty()).value(forHTTPHeaderField: "Authorization") == "Bearer k1")
        let headers = client(.headers(["CF-Access-Client-Id": "id", "CF-Access-Client-Secret": "s"])).makeRequest(method: "Init", body: Empty())
        #expect(headers.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "s")
        let cookies = client(.cookies(["olivetin-sid-oauth": "abc", "a": "1"])).makeRequest(method: "Init", body: Empty())
        #expect(cookies.value(forHTTPHeaderField: "Cookie") == "a=1; olivetin-sid-oauth=abc")
        let none = client(nil).makeRequest(method: "Init", body: Empty())
        #expect(none.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(none.httpMethod == "POST")
        #expect(none.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func repliesAreSorted() {
        let json = "application/json"
        #expect(throws: Never.self) { try ConnectClient.check(status: 200, contentType: json, body: Data("{}".utf8)) }
        #expect(throws: GatewayError.signInNeeded) { try ConnectClient.check(status: 302, contentType: "text/html", body: Data()) }
        #expect(throws: GatewayError.signInNeeded) { try ConnectClient.check(status: 401, contentType: json, body: Data()) }
        #expect(throws: GatewayError.signInNeeded) {
            try ConnectClient.check(status: 200, contentType: "text/html", body: Data("<form><input type=\"password\"></form>".utf8))
        }
        #expect(throws: GatewayError.notOliveTin) { try ConnectClient.check(status: 200, contentType: "text/html", body: Data("<h1>nginx</h1>".utf8)) }
        #expect(throws: GatewayError.notOliveTin) { try ConnectClient.check(status: 404, contentType: "text/plain", body: Data("404 page not found".utf8)) }
        #expect(throws: GatewayError.signInNeeded) {
            try ConnectClient.check(status: 403, contentType: json, body: Data(#"{"code":"permission_denied"}"#.utf8))
        }
        #expect(throws: GatewayError.refused("confirmation required")) {
            try ConnectClient.check(status: 400, contentType: json, body: Data(#"{"code":"error","message":"confirmation required"}"#.utf8))
        }
    }
}

@Suite struct StorageTests {
    /// servers.json from before the entity type was saved still reads, and leaves the choice to the app.
    @Test func olderServerFileReads() throws {
        let json = #"{"id":"8D0B8F4E-6F6B-4C38-9A63-2B1E0B6C0C11","name":"Homelab","address":"https://panel.example.ts.net","signIn":"automatic"}"#
        let server = try JSONDecoder().decode(Server.self, from: Data(json.utf8))
        #expect(server.entityType == nil)
    }

    @Test func serversRoundTripWithPrivatePermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "lamp-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = JSONServerRepository(directory: directory)
        #expect(try repository.load().isEmpty)

        let server = Server(name: "Homelab", address: URL(string: "https://panel.example.ts.net")!, signIn: .automatic)
        try repository.save([server])

        #expect(try repository.load() == [server])
        let file = try FileManager.default.attributesOfItem(atPath: directory.appending(path: "servers.json").path)
        #expect((file[.posixPermissions] as? Int) == 0o600)
        let folder = try FileManager.default.attributesOfItem(atPath: directory.path)
        #expect((folder[.posixPermissions] as? Int) == 0o700)
    }
}

/// Runs against the web Lamp's mock server: `node dev/server.mjs` in olivetin-lamp, then
/// `LAMP_MOCK_URL=http://127.0.0.1:8080 swift test`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LAMP_MOCK_URL"] != nil))
struct MockServerTests {
    let gateway = HTTPGatewayFactory().gateway(address: URL(string: ProcessInfo.processInfo.environment["LAMP_MOCK_URL"] ?? "http://127.0.0.1:8080")!, credential: nil)

    @Test func readsEverything() async throws {
        let info = try await gateway.info()
        #expect(info.isSignedIn)
        let actions = try await gateway.actions(dashboards: info.rootDashboards)
        #expect(actions.contains { $0.id == "update" && $0.requiresHold && $0.group == "Everyday" })
        let machines = try await gateway.machines(entityType: "machine")
        #expect(machines.first?.name == "nas")
        #expect(machines.first?.health == .attention)
        #expect(!(try await gateway.history()).isEmpty)
    }

    @Test func runsAndFollowsAnAction() async throws {
        let id = try await gateway.start(actionID: "notify", arguments: [:], justification: nil)
        var execution = try await gateway.execution(id: id)
        for _ in 0..<20 where !execution.isFinished {
            try await Task.sleep(for: .milliseconds(500))
            execution = try await gateway.execution(id: id)
        }
        #expect(execution.state == .succeeded)
        #expect(execution.output.contains("PLAY RECAP"))
    }

    @Test func missingConfirmationIsRefused() async {
        await #expect(throws: GatewayError.refused("confirmation required")) {
            _ = try await gateway.start(actionID: "prune", arguments: [:], justification: nil)
        }
    }
}
