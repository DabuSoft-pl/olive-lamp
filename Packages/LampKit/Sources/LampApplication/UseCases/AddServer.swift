import Foundation
import LampDomain

/// Asks an address what it is before it is saved, so the user sees at once whether the sign-in works.
@MainActor
public final class ProbeServer {
    private let directory: ServerDirectory

    public init(directory: ServerDirectory) {
        self.directory = directory
    }

    public func callAsFunction(address: URL, credential: Credential?) async throws(GatewayError) -> ServerInfo {
        do {
            return try await directory.gateway(address: address, credential: credential).info()
        } catch {
            throw GatewayError.from(error)
        }
    }
}

/// Saves a server once it answered as OliveTin, with its secret in the credential store.
@MainActor
public final class AddServer {
    private let directory: ServerDirectory
    private let probe: ProbeServer

    public init(directory: ServerDirectory, probe: ProbeServer) {
        self.directory = directory
        self.probe = probe
    }

    public func callAsFunction(
        name: String, address: URL, signIn: SignInMethod, credential: Credential?
    ) async throws(GatewayError) -> Server {
        let info = try await probe(address: address, credential: credential)
        if info.loginRequired, !info.isSignedIn { throw .signInNeeded }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let server = Server(name: trimmed.isEmpty ? Self.fallbackName(info: info, address: address) : trimmed, address: address, signIn: signIn)
        do {
            try directory.add(server, credential: signIn == .automatic ? nil : credential)
        } catch {
            throw .refused(error.localizedDescription)
        }
        return server
    }

    static func fallbackName(info: ServerInfo, address: URL) -> String {
        let title = info.title.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty, title != "OliveTin" { return title }
        return address.host() ?? address.absoluteString
    }
}
