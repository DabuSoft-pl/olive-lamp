import Foundation
import LampApplication
import LampDomain
import Security
import Synchronization

/// `actions.json` next to `servers.json`: the actions of the server the panel shows, for the Raycast extension, and the
/// token that `olivelamp://run` links need. Only the user can read it (0600); it holds no OliveTin secret.
public final class JSONActionCatalog: ActionCatalog, Sendable {
    private let file: URL
    private let current: Mutex<String>

    public var token: String { current.withLock { $0 } }

    public init(directory: URL) {
        file = directory.appending(path: "actions.json")
        // The token outlives a launch, so a Raycast command keeps working; a missing or broken file gets a new one.
        if let data = try? Data(contentsOf: file), let record = try? JSONDecoder().decode(Record.self, from: data),
           record.token.count >= 32 {
            current = Mutex(record.token)
        } else {
            current = Mutex(Self.newToken())
        }
    }

    public func publish(_ overview: Overview) throws {
        try write(Record(
            version: 1,
            token: token,
            server: .init(id: overview.server.id, name: overview.server.name, address: overview.server.address),
            actions: overview.actions.filter(\.canRun).map(Record.Entry.init)
        ))
    }

    public func clear() throws {
        try write(Record(version: 1, token: token, server: nil, actions: nil))
    }

    public func resetToken() throws {
        let token = Self.newToken()
        try write(Record(version: 1, token: token, server: nil, actions: nil))
        current.withLock { $0 = token }
    }

    private func write(_ record: Record) throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        // Created private before the token goes in, then swapped in whole.
        let temporary = directory.appending(path: ".actions-\(UUID().uuidString).json")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            try data.write(to: temporary)
            _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
            // replaceItemAt keeps the old file's mode; the token is private whatever it was.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString + UUID().uuidString
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    struct Record: Codable {
        var version: Int
        var token: String
        var server: Server?
        var actions: [Entry]?

        struct Server: Codable {
            var id: UUID
            var name: String
            /// For actions only the web page can start.
            var address: URL
        }

        struct Entry: Codable {
            var id: String
            var title: String
            var group: String?
            var section: String?
            /// Held in the panel; a caller asks the user first and sends `confirmed=1`.
            var hold: Bool
            /// OliveTin wants a reason, sent as `reason`.
            var reason: Bool
            /// Only the web page can start it.
            var opensInBrowser: Bool
            var arguments: [Argument]

            init(_ action: Action) {
                id = action.id
                title = action.title
                group = action.group
                section = action.section
                hold = action.requiresHold
                reason = action.justification != nil
                switch action.launch {
                case .direct:
                    opensInBrowser = false
                    arguments = []
                case .pick(let asked):
                    opensInBrowser = false
                    arguments = asked.map(Argument.init)
                case .inBrowser:
                    opensInBrowser = true
                    arguments = []
                }
            }
        }

        struct Argument: Codable {
            var name: String
            var title: String
            var initial: String?
            var choices: [Choice]

            init(_ argument: ActionArgument) {
                name = argument.name
                title = argument.title.isEmpty ? argument.name : argument.title
                initial = argument.initialChoice
                if case .choice(let list) = argument.kind {
                    choices = list.map { Choice(value: $0.value, title: $0.title.isEmpty ? $0.value : $0.title) }
                } else {
                    choices = []
                }
            }
        }

        struct Choice: Codable {
            var value: String
            var title: String
        }
    }
}
