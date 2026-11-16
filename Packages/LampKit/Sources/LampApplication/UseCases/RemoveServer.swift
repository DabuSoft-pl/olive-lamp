import Foundation
import LampDomain

/// Removes a server with its secret. The action catalog stops listing actions until the panel reads a server again,
/// so other programs never offer a server the user removed.
@MainActor
public final class RemoveServer {
    private let directory: ServerDirectory
    private let catalog: (any ActionCatalog)?

    public init(directory: ServerDirectory, catalog: (any ActionCatalog)?) {
        self.directory = directory
        self.catalog = catalog
    }

    public func callAsFunction(_ id: UUID) throws {
        try directory.remove(id)
        try? catalog?.clear()
    }
}

/// Gives `olivelamp://run` links a new token: links copied or seen with the old one stop working. The catalog lists
/// no actions until the panel reads its server again.
@MainActor
public final class ResetLinkToken {
    private let catalog: any ActionCatalog

    public init(catalog: any ActionCatalog) {
        self.catalog = catalog
    }

    public func callAsFunction() throws {
        try catalog.resetToken()
    }
}
