import Foundation
import LampDomain

// OliveTin's messages as Connect sends them: protobuf JSON, lowerCamelCase, and every field with its default value
// left out. So every field is optional here and the mapping fills the defaults.

struct InitReply: Decodable {
    var pageTitle: String?
    var currentVersion: String?
    var authenticatedUser: String?
    var loginRequired: Bool?
    var authLocalLogin: Bool?
    var oAuth2Providers: [Provider]?
    var rootDashboards: [String]?

    struct Provider: Decodable {
        var title: String?
        var key: String?
    }

    var info: ServerInfo {
        ServerInfo(
            title: pageTitle ?? "",
            version: currentVersion ?? "",
            user: authenticatedUser ?? "",
            loginRequired: loginRequired ?? false,
            offersLocalLogin: authLocalLogin ?? false,
            oAuthProviders: (oAuth2Providers ?? []).compactMap { $0.title ?? $0.key },
            rootDashboards: rootDashboards ?? []
        )
    }
}

struct DashboardRequest: Encodable, Sendable {
    var title: String
}

struct DashboardReply: Decodable {
    var dashboard: Dashboard?

    struct Dashboard: Decodable {
        var title: String?
        var contents: [Component]?
    }

    final class Component: Decodable {
        var title: String?
        var type: String?
        var contents: [Component]?
        var action: ActionMessage?
    }

    /// Every action on the dashboard in order, each under the top-level fieldset it sits in.
    var actions: [Action] {
        var found: [Action] = []
        func walk(_ components: [Component], group: String?, depth: Int) {
            for component in components {
                if let message = component.action, let action = message.action(group: group) {
                    found.append(action)
                }
                let title = component.title?.trimmingCharacters(in: .whitespaces)
                let isGroup = component.type == "fieldset" && depth == 0 && !(title ?? "").isEmpty
                walk(component.contents ?? [], group: isGroup ? title : group, depth: depth + 1)
            }
        }
        walk(dashboard?.contents ?? [], group: nil, depth: 0)
        return found
    }
}

struct ActionMessage: Decodable {
    var bindingId: String?
    var title: String?
    var canExec: Bool?
    var hasRunningInstance: Bool?
    var arguments: [Argument]?

    struct Argument: Decodable {
        var name: String?
        var title: String?
        var type: String?
        var choices: [Choice]?
    }

    struct Choice: Decodable {
        var value: String?
        var title: String?
    }

    func action(group: String?) -> Action? {
        guard let id = bindingId, !id.isEmpty else { return nil }
        return Action(
            id: id,
            title: title ?? id,
            group: group,
            canRun: canExec ?? false,
            isRunning: hasRunningInstance ?? false,
            arguments: (arguments ?? []).compactMap(Self.argument)
        )
    }

    static func argument(_ message: Argument) -> ActionArgument? {
        guard let name = message.name, !name.isEmpty else { return nil }
        let title = message.title.flatMap { $0.isEmpty ? nil : $0 } ?? name
        if message.type == "confirmation" { return ActionArgument(name: name, title: title, kind: .confirmation) }
        let choices = (message.choices ?? []).compactMap { choice -> ActionArgument.Choice? in
            guard let value = choice.value else { return nil }
            return ActionArgument.Choice(value: value, title: choice.title.flatMap { $0.isEmpty ? nil : $0 } ?? value)
        }
        if !choices.isEmpty { return ActionArgument(name: name, title: title, kind: .choice(choices)) }
        return ActionArgument(name: name, title: title, kind: .other(message.type ?? ""))
    }
}

struct EntitiesRequest: Encodable, Sendable {
    var entityType: String
}

struct EntitiesReply: Decodable {
    var entityDefinitions: [Definition]?

    struct Definition: Decodable {
        var title: String?
        var instances: [EntityMessage]?
    }
}

struct EntityRequest: Encodable, Sendable {
    var type: String
    var uniqueKey: String
}

struct EntityMessage: Decodable {
    var title: String?
    var uniqueKey: String?
    var fields: [String: String]?
}

struct StartRequest: Encodable, Sendable {
    var bindingId: String
    var arguments: [Argument]

    struct Argument: Encodable, Sendable {
        var name: String
        var value: String
    }
}

struct StartReply: Decodable {
    var executionTrackingId: String?
}

struct TrackingRequest: Encodable, Sendable {
    var executionTrackingId: String
}

struct StatusReply: Decodable {
    var logEntry: LogEntry?
}

struct LogsRequest: Encodable, Sendable {
    var startOffset: Int
}

struct LogsReply: Decodable {
    var logs: [LogEntry]?
}

struct LogEntry: Decodable {
    var executionTrackingId: String?
    var bindingId: String?
    var actionTitle: String?
    var user: String?
    var datetimeStarted: String?
    var datetimeFinished: String?
    var output: String?
    var exitCode: Int?
    var executionFinished: Bool?
    var queued: Bool?
    var timedOut: Bool?
    var blocked: Bool?
    var canKill: Bool?

    var execution: Execution? {
        guard let id = executionTrackingId, !id.isEmpty else { return nil }
        return Execution(
            id: id,
            actionID: bindingId ?? "",
            actionTitle: actionTitle ?? bindingId ?? "",
            user: user ?? "",
            startedAt: OliveTinTime.parse(datetimeStarted),
            finishedAt: OliveTinTime.parse(datetimeFinished),
            output: output ?? "",
            exitCode: exitCode ?? 0,
            isFinished: executionFinished ?? false,
            isQueued: queued ?? false,
            timedOut: timedOut ?? false,
            blocked: blocked ?? false,
            canKill: canKill ?? false
        )
    }
}
