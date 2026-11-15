import Foundation
import LampDomain

/// Turns the cookies a sign-in page left behind into the credential Lamp keeps: only those a browser would send to
/// the server, so an OAuth provider's own cookies never reach the Keychain.
public enum SessionCookies {
    public static func credential(from cookies: [HTTPCookie], for address: URL) -> Credential? {
        guard let host = address.host()?.lowercased() else { return nil }
        var values: [String: String] = [:]
        for cookie in cookies where !(cookie.expiresDate.map { $0 < .now } ?? false) {
            let domain = String(cookie.domain.lowercased().trimmingPrefix("."))
            if host == domain || host.hasSuffix("." + domain) { values[cookie.name] = cookie.value }
        }
        return values.isEmpty ? nil : .cookies(values)
    }
}
