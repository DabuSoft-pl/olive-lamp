import Foundation

/// One run of an action, as OliveTin's log entry describes it.
public struct Execution: Identifiable, Equatable, Sendable {
    /// OliveTin's execution tracking id.
    public let id: String
    public var actionID: String
    public var actionTitle: String
    public var user: String
    public var startedAt: Date?
    public var finishedAt: Date?
    public var output: String
    public var exitCode: Int
    public var isFinished: Bool
    public var isQueued: Bool
    public var timedOut: Bool
    public var blocked: Bool
    public var canKill: Bool

    public init(
        id: String, actionID: String, actionTitle: String, user: String = "", startedAt: Date? = nil,
        finishedAt: Date? = nil, output: String = "", exitCode: Int = 0, isFinished: Bool = false,
        isQueued: Bool = false, timedOut: Bool = false, blocked: Bool = false, canKill: Bool = false
    ) {
        self.id = id
        self.actionID = actionID
        self.actionTitle = actionTitle
        self.user = user
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.output = output
        self.exitCode = exitCode
        self.isFinished = isFinished
        self.isQueued = isQueued
        self.timedOut = timedOut
        self.blocked = blocked
        self.canKill = canKill
    }

    public enum State: Equatable, Sendable {
        case queued, running, succeeded, failed, timedOut, blocked
    }

    public var state: State {
        if blocked { return .blocked }
        if isQueued, !isFinished { return .queued }
        if !isFinished { return .running }
        if timedOut { return .timedOut }
        return exitCode == 0 ? .succeeded : .failed
    }

    public var isActive: Bool { state == .running || state == .queued }

    /// Running time so far, or the whole run once it finished.
    public func elapsed(at now: Date) -> TimeInterval? {
        guard let startedAt else { return nil }
        let end = isFinished ? (finishedAt ?? now) : now
        return max(0, end.timeIntervalSince(startedAt))
    }

    public var duration: TimeInterval? {
        guard isFinished, let startedAt, let finishedAt else { return nil }
        return max(0, finishedAt.timeIntervalSince(startedAt))
    }

    /// A finished run is worth a notification when it went wrong, or took long enough for the user to look away.
    public func deservesNotice(longerThan seconds: TimeInterval = 20) -> Bool {
        guard isFinished else { return false }
        if state != .succeeded { return true }
        return (duration ?? 0) >= seconds
    }

    /// The last lines of output that say something.
    /// The last lines worth reading at a glance: colour codes gone, filler rules like Ansible's "Task ------ 0.30s"
    /// squeezed to "Task · 0.30s", and lines of nothing but punctuation skipped. The full log stays as it was.
    public func tail(_ count: Int) -> [String] {
        let lines = output.split(whereSeparator: \.isNewline).compactMap { Self.readable(String($0)) }
        return Array(lines.suffix(count))
    }

    static func readable(_ line: String) -> String? {
        var text = line.replacing(/\u{1B}\[[0-9;?]*[A-Za-z]/, with: "")
        text = text.replacing(/\s*[-*=_~.]{4,}\s*/, with: " · ")
        text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("· ") { text.removeFirst(2) }
        if text.hasSuffix(" ·") { text.removeLast(2) }
        guard text.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        return text
    }
}

/// How long a run will take, judged by earlier successful runs of the same action.
public struct RunEstimate: Equatable, Sendable {
    /// The typical duration: the median of the last successful runs.
    public let typical: TimeInterval

    public init?(history: [Execution], actionID: String, considering limit: Int = 5) {
        let durations = history
            .filter { $0.actionID == actionID && $0.state == .succeeded }
            .compactMap(\.duration)
            .filter { $0 > 0 }
            .prefix(limit)
            .sorted()
        guard !durations.isEmpty else { return nil }
        let middle = durations.count / 2
        typical = durations.count.isMultiple(of: 2) ? (durations[middle - 1] + durations[middle]) / 2 : durations[middle]
    }

    /// Share done so far. It stops short of full, since only the server knows when the run ends.
    public func progress(elapsed: TimeInterval) -> Double {
        min(max(elapsed / typical, 0), 0.95)
    }

    /// Time left, or nil once the run takes longer than usual.
    public func remaining(elapsed: TimeInterval) -> TimeInterval? {
        let left = typical - elapsed
        return left > 0 ? left : nil
    }
}
