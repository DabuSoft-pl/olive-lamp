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

    /// A server-streaming call: Connect frames each message as one flag byte, a big-endian length and the JSON. The last
    /// frame (flag 2) ends the stream and may carry an error.
    func stream<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        _ method: String, _ request: Request, as: Response.Type = Response.self
    ) -> AsyncThrowingStream<Response, any Error> {
        var urlRequest = makeRequest(method: method, body: request)
        let json = urlRequest.httpBody ?? Data("{}".utf8)
        urlRequest.httpBody = Self.frame(json)
        urlRequest.setValue("application/connect+json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/connect+json", forHTTPHeaderField: "Accept")
        // The server sends a heartbeat every 10 s; this long without a byte means the connection is gone.
        urlRequest.timeoutInterval = 35
        let session = session
        let streamRequest = urlRequest
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: streamRequest, delegate: NoRedirects.shared)
                    guard let http = response as? HTTPURLResponse else { throw GatewayError.notOliveTin }
                    let contentType = http.value(forHTTPHeaderField: "Content-Type")
                    guard http.statusCode == 200, contentType?.lowercased().hasPrefix("application/connect+json") == true else {
                        var body = Data()
                        for try await byte in bytes.prefix(64 * 1024) { body.append(byte) }
                        try Self.check(status: http.statusCode, contentType: contentType, body: body)
                        throw GatewayError.notOliveTin
                    }
                    var buffer = Data()
                    for try await byte in bytes {
                        buffer.append(byte)
                        while let (flags, message) = Self.unframe(&buffer) {
                            if flags & 2 != 0 {
                                if let end = try? JSONDecoder().decode(EndOfStream.self, from: message), let error = end.error {
                                    let code = error.code ?? ""
                                    throw (code == "unauthenticated" || code == "permission_denied")
                                        ? GatewayError.signInNeeded : GatewayError.refused(error.message ?? code)
                                }
                                continuation.finish()
                                return
                            }
                            continuation.yield(try JSONDecoder().decode(Response.self, from: message))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func frame(_ message: Data) -> Data {
        var data = Data([0])
        withUnsafeBytes(of: UInt32(message.count).bigEndian) { data.append(contentsOf: $0) }
        return data + message
    }

    /// Takes one whole frame off the front of `buffer`, or nil while it is still incomplete.
    static func unframe(_ buffer: inout Data) -> (flags: UInt8, message: Data)? {
        guard buffer.count >= 5 else { return nil }
        let start = buffer.startIndex
        let length = buffer[start + 1 ..< start + 5].reduce(0) { $0 << 8 | Int($1) }
        guard buffer.count >= 5 + length else { return nil }
        let flags = buffer[start]
        let message = Data(buffer[start + 5 ..< start + 5 + length])
        buffer = Data(buffer.dropFirst(5 + length))
        return (flags, message)
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

/// The last frame of a Connect stream.
struct EndOfStream: Decodable {
    var error: ConnectError?
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
