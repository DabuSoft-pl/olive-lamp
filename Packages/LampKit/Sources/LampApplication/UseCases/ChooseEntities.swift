import Foundation
import LampDomain

/// Picks which OliveTin entities the panel lists for the selected server: one type, none, or (nil) the app's own pick.
@MainActor
public final class ChooseEntities {
    private let directory: ServerDirectory

    public init(directory: ServerDirectory) {
        self.directory = directory
    }

    /// `type` is an entity type, "" for none, or nil to let the app pick.
    public func callAsFunction(_ type: String?) throws {
        guard var server = directory.selected else { return }
        server.entityType = type
        try directory.update(server)
    }
}
