import Foundation
import LampDomain

/// An action started from outside the panel, such as Raycast, through
/// `olivelamp://run?token=…&server=…&action=…[&confirmed=1][&reason=…][&arg.<name>=<value>…]`.
///
/// Any web page can open a link, so a link counts only with the token from the action catalog, which only the user's
/// own programs can read. An action that wants a hold in the panel wants `confirmed=1`: the caller asked the user.
public struct RunRequest: Equatable, Sendable {
    public var token: String
    public var server: UUID?
    public var actionID: String
    public var confirmed: Bool
    public var reason: String?
    public var arguments: [String: String]

    public enum Problem: Error, Equatable, Sendable {
        case wrongToken
        case unknownAction
        case cannotRun
        case needsConfirmation
        case needsBrowser
        case notAChoice(String)
    }

    public init(token: String, server: UUID?, actionID: String, confirmed: Bool, reason: String?, arguments: [String: String]) {
        self.token = token
        self.server = server
        self.actionID = actionID
        self.confirmed = confirmed
        self.reason = reason
        self.arguments = arguments
    }

    public init?(url: URL) {
        guard url.scheme == "olivelamp", url.host() == "run",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        var values: [String: String] = [:]
        var arguments: [String: String] = [:]
        for item in items {
            guard let value = item.value else { continue }
            if item.name.hasPrefix("arg.") {
                arguments[String(item.name.dropFirst(4))] = value
            } else {
                values[item.name] = value
            }
        }
        guard let token = values["token"], !token.isEmpty, let action = values["action"], !action.isEmpty else { return nil }
        self.token = token
        server = values["server"].flatMap(UUID.init(uuidString:))
        actionID = action
        confirmed = values["confirmed"] == "1"
        reason = values["reason"]
        self.arguments = arguments
    }

    /// The token must match the catalog's, compared without leaking how much of it matched.
    public func check(token expected: String) throws(Problem) {
        let given = Array(token.utf8), wanted = Array(expected.utf8)
        guard !wanted.isEmpty, given.count == wanted.count else { throw .wrongToken }
        var difference: UInt8 = 0
        for (a, b) in zip(given, wanted) { difference |= a ^ b }
        guard difference == 0 else { throw .wrongToken }
    }

    /// The picks for `action`, every one of them among its choices; arguments the action does not ask for are ignored.
    public func picks(for action: Action) throws(Problem) -> [String: String] {
        guard action.canRun else { throw .cannotRun }
        if action.requiresHold, !confirmed { throw .needsConfirmation }
        switch action.launch {
        case .inBrowser:
            throw .needsBrowser
        case .direct:
            return [:]
        case .pick(let asked):
            var picks: [String: String] = [:]
            for argument in asked {
                guard let value = arguments[argument.name] else { continue }
                guard case .choice(let choices) = argument.kind, choices.contains(where: { $0.value == value }) else {
                    throw .notAChoice(argument.title)
                }
                picks[argument.name] = value
            }
            return picks
        }
    }
}

/// Where the actions of the shown server are listed for other programs on this Mac, with the token their links need.
public protocol ActionCatalog: Sendable {
    var token: String { get }
    func publish(_ overview: Overview) throws
}
