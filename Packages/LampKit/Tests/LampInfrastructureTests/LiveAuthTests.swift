import CryptoKit
import Foundation
import Testing
import LampApplication
import LampDomain
@testable import LampInfrastructure

/// Every sign-in Olive Lamp offers, against the local OliveTin in dev/auth (its config.yaml says how to start it):
/// `OLIVETIN_AUTH_URL=http://127.0.0.1:1339 swift test`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["OLIVETIN_AUTH_URL"] != nil), .serialized)
struct LiveAuthTests {
    let address = URL(string: ProcessInfo.processInfo.environment["OLIVETIN_AUTH_URL"] ?? "http://127.0.0.1:1339")!

    func gateway(_ credential: Credential?) -> any OliveTinGateway {
        HTTPGatewayFactory().gateway(address: address, credential: credential)
    }

    @Test func guestMustSignIn() async throws {
        let info = try await gateway(nil).info()
        #expect(info.loginRequired)
        #expect(!info.isSignedIn)
    }

    /// A run's start, output and end arrive on the EventStream while it happens.
    @Test func eventStreamTellsARunAsItHappens() async throws {
        let gateway = gateway(.apiKey("olivelamp-test-key-0123456789abcdef"))
        let hello = try #require(try await gateway.actions(dashboards: try await gateway.info().rootDashboards).first { $0.title == "Say hello" })
        let seen = Task {
            var events: [ServerEvent] = []
            for try await event in gateway.events() {
                events.append(event)
                if case .executionFinished = event { break }
                if events.count == 1 { _ = try await gateway.start(actionID: hello.id, arguments: [:], justification: nil) }
            }
            return events
        }
        let timeout = Task { try await Task.sleep(for: .seconds(20)); seen.cancel() }
        let events = try await seen.value
        timeout.cancel()
        #expect(events.first == .heartbeat)
        #expect(events.contains { if case .executionStarted(let e) = $0 { e.actionID == hello.id } else { false } })
        #expect(events.contains { if case .executionFinished(let e) = $0 { e.actionID == hello.id && e.isFinished } else { false } })
    }

    @Test func apiKeyRunsAnAction() async throws {
        let gateway = gateway(.apiKey("olivelamp-test-key-0123456789abcdef"))
        #expect(try await gateway.info().user == "automation")
        let actions = try await gateway.actions(dashboards: try await gateway.info().rootDashboards)
        let hello = try #require(actions.first { $0.title == "Say hello" })
        let id = try await gateway.start(actionID: hello.id, arguments: [:], justification: nil)
        var execution = try await gateway.execution(id: id)
        for _ in 0..<20 where !execution.isFinished {
            try await Task.sleep(for: .milliseconds(250))
            execution = try await gateway.execution(id: id)
        }
        #expect(execution.state == .succeeded)
        #expect(execution.output.contains("hello from OliveTin"))
    }

    @Test func wrongApiKeyIsAGuest() async throws {
        let info = try? await gateway(.apiKey("not-the-key")).info()
        #expect(info?.isSignedIn != true)
    }

    @Test func trustedHeaderFromAProxy() async throws {
        #expect(try await gateway(.headers(["X-Username": "proxy-user"])).info().user == "proxy-user")
    }

    @Test func jwtCookieAsHeaders() async throws {
        let token = Self.jwt(["username": "jwt-user", "usergroup": "admins", "exp": Int(Date().timeIntervalSince1970) + 600])
        #expect(try await gateway(.headers(["Cookie": "lamp_jwt=\(token)"])).info().user == "jwt-user")
    }

    /// What Web sign-in keeps after the server's own login page: the session cookie.
    @Test func localUserSession() async throws {
        var request = URLRequest(url: address.appending(path: "api/LocalUserLogin"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"username":"admin","password":"lamp-test"}"#.utf8)
        request.httpShouldHandleCookies = false
        let (_, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        let fields = (response as? HTTPURLResponse)?.allHeaderFields as? [String: String] ?? [:]
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: address)
        let session = try #require(cookies.first { $0.name == "olivetin-sid-local" })
        let credential = try #require(SessionCookies.credential(from: cookies, for: address))
        #expect(credential == .cookies(["olivetin-sid-local": session.value]))
        #expect(try await gateway(credential).info().user == "admin")
    }

    static func jwt(_ claims: [String: Any]) -> String {
        func encode(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = encode(Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8))
        let body = encode(try! JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys]))
        let key = SymmetricKey(data: Data("olivelamp-test-secret-not-for-real-use".utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data("\(header).\(body)".utf8), using: key)
        return "\(header).\(body).\(encode(Data(signature)))"
    }
}
