import Foundation
import LampDomain

/// The actions of one machine (one OliveTin entity) on the selected server, read when the user opens it. When OliveTin
/// binds none to it, the server's actions whose list offers the machine stand in, set to it.
@MainActor
public final class LoadMachineActions {
    private let directory: ServerDirectory

    public init(directory: ServerDirectory) {
        self.directory = directory
    }

    public func callAsFunction(
        _ machine: Machine, entityType: String, offered: [Action] = []
    ) async throws(GatewayError) -> [Action] {
        guard let server = directory.selected else { return [] }
        let bound: [Action]
        do {
            bound = try await directory.gateway(for: server).relatedActions(entityType: entityType, key: machine.id)
        } catch {
            throw GatewayError.from(error)
        }
        let actions = bound.isEmpty ? offered.compactMap { $0.aimed(at: machine) } : bound
        return actions.filter(\.canRun)
    }
}
