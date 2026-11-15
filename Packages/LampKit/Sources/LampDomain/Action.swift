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
        if asked.count == 1, case .choice(let choices) = asked[0].kind, !choices.isEmpty { return .pick(asked[0]) }
        return .inBrowser
    }

    /// The arguments to send: the user's pick, and "1" for the confirmation (it guards against accidents, not access).
    public func startArguments(picked: String? = nil) -> [String: String] {
        var values: [String: String] = [:]
        for argument in arguments {
            switch argument.kind {
            case .confirmation:
                values[argument.name] = "1"
            case .choice:
                if let picked { values[argument.name] = picked }
            case .other:
                break
            }
        }
        return values
    }

    public enum Launch: Equatable, Sendable {
        case direct
        /// One list of choices, picked from a menu.
        case pick(ActionArgument)
        /// Free text or several arguments: the web page asks better than a menu.
        case inBrowser
    }
}

public struct ActionArgument: Equatable, Sendable {
    public var name: String
    public var title: String
    public var kind: Kind

    public init(name: String, title: String, kind: Kind) {
        self.name = name
        self.title = title
        self.kind = kind
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
