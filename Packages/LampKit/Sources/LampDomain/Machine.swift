import Foundation

/// A machine the dashboard shows, read from an OliveTin entity. The field names follow the web Lamp's convention
/// (`state`, `meta`, `summary` or `label`, `kind`), so the same status playbook feeds both.
public struct Machine: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var kind: String?
    public var health: Health
    /// A short note, like "3 updates" or "reboot".
    public var note: String?

    public init(id: String, name: String, kind: String? = nil, health: Health = .unknown, note: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.health = health
        self.note = note
    }

    public enum Health: Equatable, Sendable {
        case ok, attention, failing, off, unknown
    }

    /// Reads any OliveTin entity. Field names are matched without regard to case, so the web Lamp's status playbook
    /// (`state`, `meta`, `summary`, `label`, `kind`) and, say, Docker's (`Names`, `State`, `Status`, `Image`) both read.
    public init(key: String, title: String, fields: [String: String]) {
        var lower: [String: String] = [:]
        for (name, value) in fields {
            let text = value.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { lower[name.lowercased()] = text }
        }
        func first(_ names: String...) -> String? { names.lazy.compactMap { lower[$0] }.first }
        let state = first("state", "status")
        let health = Self.health(from: state)
        // A machine that is fine needs no sentence; one that is not says why, the playbook's words before the badge.
        let status = lower["status"].flatMap { $0.lowercased() == state?.lowercased() ? nil : $0 }
        let candidates = health == .ok ? [lower["meta"]] : [lower["meta"], lower["summary"], status, lower["label"]]
        self.init(
            id: key,
            name: first("name", "names", "hostname") ?? title,
            kind: first("kind", "type", "image"),
            health: health,
            note: candidates.compactMap { $0 }.first { $0.lowercased() != "ok" }
        )
    }

    static func health(from state: String?) -> Health {
        switch state?.lowercased() {
        case "ok", "up", "online", "running", "healthy", "active": .ok
        case "warn", "warning", "attention", "paused", "restarting", "degraded", "unhealthy": .attention
        case "bad", "fail", "failed", "error", "down", "unreachable", "dead": .failing
        case "off", "stopped", "offline", "exited", "created", "inactive": .off
        default: .unknown
        }
    }
}
