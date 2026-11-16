import Foundation
import LampDomain

/// Turns the cookies a sign-in page left behind into the credential Lamp keeps: only those a browser would send with
/// Lamp's requests to the server (`<address>/api/…`), so an OAuth provider's own cookies never reach the Keychain, and a
/// `Secure` cookie never goes out over plain HTTP.
public enum SessionCookies {
    public static func credential(from cookies: [HTTPCookie], for address: URL) -> Credential? {
        guard let host = address.host()?.lowercased() else { return nil }
        let encrypted = address.scheme?.lowercased() == "https"
        var base = address.path
        if !base.hasSuffix("/") { base += "/" }
        let path = base + "api/"
        let sent = cookies.filter { cookie in
            !(cookie.expiresDate.map { $0 < .now } ?? false) && (encrypted || !cookie.isSecure)
                && domain(cookie.domain, matches: host) && self.path(cookie.path, matches: path)
        }
        // Two with one name: the more specific one wins, as a browser sends it first.
        var values: [String: String] = [:]
        for cookie in sent.sorted(by: { ($0.path.count, $0.domain.count) < ($1.path.count, $1.domain.count) }) {
            values[cookie.name] = cookie.value
        }
        return values.isEmpty ? nil : .cookies(values)
    }

    /// A cookie set with a Domain attribute (kept with a leading dot) goes to that domain and below it; one without goes
    /// only to the host that set it.
    static func domain(_ domain: String, matches host: String) -> Bool {
        let domain = domain.lowercased()
        guard domain.hasPrefix(".") else { return host == domain }
        return host == domain.dropFirst() || host.hasSuffix(domain)
    }

    /// RFC 6265 path match: the cookie's path is the request path or a directory above it.
    static func path(_ cookiePath: String, matches path: String) -> Bool {
        let cookiePath = cookiePath.isEmpty ? "/" : cookiePath
        guard path.hasPrefix(cookiePath) else { return false }
        return path.count == cookiePath.count || cookiePath.hasSuffix("/") || path.dropFirst(cookiePath.count).first == "/"
    }
}
