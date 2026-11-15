import Foundation
import LampDomain

/// Keeps a new session or key for a server whose sign-in expired, once the server says it knows the user.
@MainActor
public final class SignInAgain {
    private let directory: ServerDirectory
    private let probe: ProbeServer

    public init(directory: ServerDirectory, probe: ProbeServer) {
        self.directory = directory
        self.probe = probe
    }

    @discardableResult
    public func callAsFunction(_ server: Server, credential: Credential) async throws(GatewayError) -> ServerInfo {
        let info = try await probe(address: server.address, credential: credential)
        if info.loginRequired, !info.isSignedIn { throw .signInNeeded }
        do {
            try directory.updateCredential(credential, for: server)
        } catch {
            throw .refused(error.localizedDescription)
        }
        return info
    }
}
