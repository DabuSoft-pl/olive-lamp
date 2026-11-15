import Foundation

/// One OliveTin server the app talks to. Secrets are never stored here, only in the credential store.
public struct Server: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var address: URL
    public var signIn: SignInMethod
    /// Which OliveTin entities the panel lists: nil picks one by itself, "" lists none.
    public var entityType: String?

    public init(id: UUID = UUID(), name: String, address: URL, signIn: SignInMethod, entityType: String? = nil) {
        self.id = id
        self.name = name
        self.address = address
        self.signIn = signIn
        self.entityType = entityType
    }

    /// The entity type to list out of what the server offers: the user's choice, else `machine` (the web Lamp's status
    /// playbook), else the first type. nil lists none.
    public func entityType(among offered: [String]) -> String? {
        if let entityType { return entityType.isEmpty || !offered.contains(entityType) ? nil : entityType }
        return offered.contains("machine") ? "machine" : offered.first
    }
}

/// How the app proves who the user is.
public enum SignInMethod: String, Codable, Sendable, CaseIterable {
    /// Nothing to send: a guest, or trusted headers a proxy adds by itself (Tailscale Serve).
    case automatic
    /// `Authorization: Bearer <key>` of an OliveTin local user.
    case apiKey
    /// Headers of the user's choice: a JWT, a Cloudflare Access service token.
    case headers
    /// Cookies kept from signing in on the server's own web page.
    case webSession

    /// Whether this method sends a secret with every request.
    public var sendsSecret: Bool { self != .automatic }
}

public extension URL {
    /// Plain HTTP to anything but this Mac: whoever shares the network can read what is sent.
    var isCleartextToAnotherHost: Bool {
        guard scheme?.lowercased() == "http" else { return false }
        let host = (host() ?? "").lowercased()
        return !["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }
}

/// What the app keeps in the Keychain for a server.
public enum Credential: Equatable, Codable, Sendable {
    case apiKey(String)
    case headers([String: String])
    case cookies([String: String])
}

/// What a server says about itself before anything else is asked.
public struct ServerInfo: Equatable, Sendable {
    public var title: String
    public var version: String
    /// Empty for a guest.
    public var user: String
    public var loginRequired: Bool
    public var offersLocalLogin: Bool
    public var oAuthProviders: [String]
    public var rootDashboards: [String]

    public init(
        title: String, version: String, user: String, loginRequired: Bool,
        offersLocalLogin: Bool, oAuthProviders: [String], rootDashboards: [String]
    ) {
        self.title = title
        self.version = version
        self.user = user
        self.loginRequired = loginRequired
        self.offersLocalLogin = offersLocalLogin
        self.oAuthProviders = oAuthProviders
        self.rootDashboards = rootDashboards
    }

    /// The server already knows who is asking, so there is nothing to set up.
    public var isSignedIn: Bool { !user.isEmpty && user != "guest" }
}
