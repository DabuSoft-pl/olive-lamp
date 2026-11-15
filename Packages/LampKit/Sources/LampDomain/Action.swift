/// An OliveTin action the user may run.
public struct Action: Identifiable, Equatable, Sendable {
    /// OliveTin's binding id.
    public let id: String
    public var title: String
    /// The fieldset the action sits in on its dashboard, if any.
    public var group: String?
    public var canRun: Bool
    public var isRunning: Bool
    public var arguments: [ActionArgument]

    public init(id: String, title: String, group: String? = nil, canRun: Bool = true, isRunning: Bool = false, arguments: [ActionArgument] = []) {
        self.id = id
        self.title = title
        self.group = group
        self.canRun = canRun
        self.isRunning = isRunning
        self.arguments = arguments
    }

    /// An action with a named confirmation changes something: it runs only after the user holds it.
    public var requiresHold: Bool { arguments.contains { $0.kind == .confirmation } }

    /// How the app can start the action.
    public var launch: Launch {
        let asked = arguments.filter { $0.kind != .confirmation }
        if asked.isEmpty { return .direct }
        let lists = asked.allSatisfy { if case .choice(let choices) = $0.kind { !choices.isEmpty } else { false } }
        return lists ? .pick(asked) : .inBrowser
    }

    /// The arguments to send: the user's picks by argument name (else the list's default), and "1" for the
    /// confirmation (it guards against accidents, not access).
    public func startArguments(picked: [String: String] = [:]) -> [String: String] {
        var values: [String: String] = [:]
        for argument in arguments {
            switch argument.kind {
            case .confirmation:
                values[argument.name] = "1"
            case .choice:
                if let value = picked[argument.name] ?? argument.initialChoice { values[argument.name] = value }
            case .other:
                break
            }
        }
        return values
    }

    public enum Launch: Equatable, Sendable {
        case direct
        /// One or more lists of choices, each picked from a menu.
        case pick([ActionArgument])
        /// Free text or another kind of argument: the web page asks better than a menu.
        case inBrowser
    }
}

public struct ActionArgument: Equatable, Sendable {
    public var name: String
    public var title: String
    public var kind: Kind
    /// The value OliveTin preselects, if the action's config gives one.
    public var defaultValue: String?

    public init(name: String, title: String, kind: Kind, defaultValue: String? = nil) {
        self.name = name
        self.title = title
        self.kind = kind
        self.defaultValue = defaultValue
    }

    /// What a list starts at: the configured default when it is one of the choices, else the first choice.
    public var initialChoice: String? {
        guard case .choice(let choices) = kind else { return nil }
        if let defaultValue, choices.contains(where: { $0.value == defaultValue }) { return defaultValue }
        return choices.first?.value
    }

    public enum Kind: Equatable, Sendable {
        case confirmation
        case choice([Choice])
        case other(String)
    }

    public struct Choice: Identifiable, Equatable, Sendable {
        public var value: String
        public var title: String
        public var id: String { value }

        public init(value: String, title: String) {
            self.value = value
            self.title = title
        }
    }
}
