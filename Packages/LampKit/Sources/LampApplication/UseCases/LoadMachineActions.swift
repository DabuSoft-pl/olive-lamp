import Foundation
import LampDomain

/// The actions of one machine (one OliveTin entity) on the selected server, read when the user opens it.
@MainActor
public final class LoadMachineActions {
    private let directory: ServerDirectory

    public init(directory: ServerDirectory) {
        self.directory = directory
    }

    public func callAsFunction(_ machine: Machine, entityType: String) async throws(GatewayError) -> [Action] {
        guard let server = directory.selected else { return [] }
        do {
            return try await directory.gateway(for: server).relatedActions(entityType: entityType, key: machine.id)
                .filter(\.canRun)
        } catch {
            throw GatewayError.from(error)
        }
    }
}
