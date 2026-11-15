import Foundation
import LampApplication
import LampDomain

/// Calls OliveTin's API the way its web page does: Connect RPC, one JSON `POST` per method.
struct ConnectClient: Sendable {
    let address: URL
    let credential: Credential?
    let session: URLSession

    static let service = "api/olivetin.api.v1.OliveTinApiService/"

    func call<Request: Encodable & Sendable, Response: Decodable>(
        _ method: String, _ request: Request, as: Response.Type = Response.self
    ) async throws(GatewayError) -> Response {
        let urlRequest = makeRequest(method: method, body: request)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest, delegate: NoRedirects.shared)
        } catch {
            throw .unreachable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw .notOliveTin }
        try Self.check(status: http.statusCode, contentType: http.value(forHTTPHeaderField: "Content-Type"), body: data)
        do {
            return try JSONDecoder().decode(Response.self, from: data.isEmpty ? Data("{}".utf8) : data)
        } catch {
            throw .notOliveTin
        }
    }

    func makeRequest(method: String, body: some Encodable) -> URLRequest {
        var request = URLRequest(url: Self.endpoint(address: address, method: method), timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpBody = (try? JSONEncoder().encode(body)) ?? Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpShouldHandleCookies = false
        switch credential {
        case .apiKey(let key):
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .headers(let headers):
            for (name, value) in headers.sorted(by: { $0.key < $1.key }) where !name.isEmpty {
                request.setValue(value, forHTTPHeaderField: name)
            }
        case .cookies(let cookies):
            let line = cookies.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
            if !line.isEmpty { request.setValue(line, forHTTPHeaderField: "Cookie") }
        case nil:
            break
        }
        return request
    }

    static func endpoint(address: URL, method: String) -> URL {
        var base = address.absoluteString
        if !base.hasSuffix("/") { base += "/" }
        return URL(string: base + service + method) ?? address
    }

    /// Sorts a reply into success or one of our errors, before anything is decoded.
    static func check(status: Int, contentType: String?, body: Data) throws(GatewayError) {
        let isJSON = contentType?.lowercased().contains("json") ?? false
        switch status {
        case 200..<300:
            // A proxy's login page answers 200 with HTML.
            if !isJSON, !body.isEmpty { throw looksLikeLoginPage(body) ? .signInNeeded : .notOliveTin }
        case 300..<400, 401, 403:
            throw .signInNeeded
        default:
            guard isJSON, let error = try? JSONDecoder().decode(ConnectError.self, from: body) else { throw .notOliveTin }
            switch error.code {
            case "unauthenticated", "permission_denied": throw .signInNeeded
            default: throw .refused(error.message ?? error.code ?? "HTTP \(status)")
            }
        }
    }

    private static func looksLikeLoginPage(_ body: Data) -> Bool {
        let text = String(decoding: body.prefix(64 * 1024), as: UTF8.self).lowercased()
        return text.contains("type=\"password\"") || text.contains("sign in") || text.contains("log in") || text.contains("login")
    }
}

struct ConnectError: Decodable {
    var code: String?
    var message: String?
}

struct Empty: Codable, Sendable {}

/// A redirect means a proxy sends us to its login page; the app must not follow it with the user's secrets.
final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = NoRedirects()

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
