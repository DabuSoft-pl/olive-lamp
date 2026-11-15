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

    public init(key: String, title: String, fields: [String: String]) {
        let health = Self.health(from: fields["state"])
        // A machine that is fine needs no sentence; one that is not gets the playbook's `summary` before its badge.
        let candidates = health == .ok ? [fields["meta"]] : [fields["meta"], fields["summary"], fields["label"]]
        let note = candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && $0.lowercased() != "ok" }
        self.init(
            id: key,
            name: fields["name"].flatMap { $0.isEmpty ? nil : $0 } ?? title,
            kind: fields["kind"].flatMap { $0.isEmpty ? nil : $0 },
            health: health,
            note: note
        )
    }

    static func health(from state: String?) -> Health {
        switch state?.lowercased() {
        case "ok", "up", "online", "running": .ok
        case "warn", "warning", "attention": .attention
        case "bad", "fail", "failed", "error", "down", "unreachable": .failing
        case "off", "stopped", "offline": .off
        default: .unknown
        }
    }
}
