import Foundation
import LampApplication
import LampDomain

/// `servers.json` in Application Support: names, addresses and sign-in methods, never secrets.
public struct JSONServerRepository: ServerRepository {
    private let file: URL

    public init(directory: URL) {
        file = directory.appending(path: "servers.json")
    }

    public static func defaultDirectory() -> URL {
        URL.applicationSupportDirectory.appending(path: "Lamp", directoryHint: .isDirectory)
    }

    public func load() throws -> [Server] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode(Record.self, from: Data(contentsOf: file)).servers
    }

    public func save(_ servers: [Server]) throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Record(version: 1, servers: servers)).write(to: file, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private struct Record: Codable {
        var version: Int
        var servers: [Server]
    }
}

public struct SystemClock: Clock {
    public init() {}

    public var now: Date { Date() }

    public func sleep(seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}
