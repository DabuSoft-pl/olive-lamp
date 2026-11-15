import Foundation
import Testing
@testable import LampDomain

@Suite struct CleartextTests {
    @Test func plainHTTPToAnotherHostIsCleartext() {
        #expect(URL(string: "http://192.168.1.10:1337")!.isCleartextToAnotherHost)
        #expect(URL(string: "http://olivetin.local")!.isCleartextToAnotherHost)
        #expect(!URL(string: "https://panel.example.ts.net")!.isCleartextToAnotherHost)
        #expect(!URL(string: "http://localhost:1337")!.isCleartextToAnotherHost)
        #expect(!URL(string: "http://127.0.0.1:1337")!.isCleartextToAnotherHost)
        #expect(SignInMethod.apiKey.sendsSecret && !SignInMethod.automatic.sendsSecret)
    }
}

@Suite struct ActionTests {
    let machine = ActionArgument(name: "limit", title: "Machine", kind: .choice([.init(value: "nas", title: "nas"), .init(value: "all", title: "All")]))
    let confirm = ActionArgument(name: "confirm", title: "I understand", kind: .confirmation)

    @Test func runsDirectlyWithoutArguments() {
        let action = Action(id: "check", title: "Check")
        #expect(action.launch == .direct)
        #expect(!action.requiresHold)
        #expect(action.startArguments().isEmpty)
    }

    @Test func confirmationMeansHoldAndSendsOne() {
        let action = Action(id: "prune", title: "Prune", arguments: [confirm])
        #expect(action.launch == .direct)
        #expect(action.requiresHold)
        #expect(action.startArguments() == ["confirm": "1"])
    }

    @Test func oneChoiceIsPickedFromAMenu() {
        let action = Action(id: "update", title: "Update", arguments: [machine, confirm])
        #expect(action.launch == .pick([machine]))
        #expect(action.startArguments(picked: ["limit": "nas"]) == ["limit": "nas", "confirm": "1"])
        #expect(action.startArguments() == ["limit": "nas", "confirm": "1"])
    }

    @Test func severalListsArePickedEachWithItsDefault() {
        let mode = ActionArgument(name: "mode", title: "Mode", kind: .choice([.init(value: "cold", title: "cold"), .init(value: "reboot", title: "reboot")]), defaultValue: "reboot")
        let action = Action(id: "restart", title: "Restart", arguments: [machine, mode, confirm])
        #expect(action.launch == .pick([machine, mode]))
        #expect(action.startArguments(picked: ["limit": "all"]) == ["limit": "all", "mode": "reboot", "confirm": "1"])
    }

    @Test func freeTextGoesToTheBrowser() {
        let text = ActionArgument(name: "message", title: "Message", kind: .other("ascii"))
        #expect(Action(id: "a", title: "A", arguments: [text]).launch == .inBrowser)
        #expect(Action(id: "b", title: "B", arguments: [machine, text]).launch == .inBrowser)
        #expect(Action(id: "c", title: "C", arguments: [ActionArgument(name: "x", title: "X", kind: .choice([]))]).launch == .inBrowser)
    }
}

@Suite struct ExecutionTests {
    let start = Date(timeIntervalSince1970: 1_000)

    func run(finished: Bool, exit: Int = 0, seconds: Double = 60, timedOut: Bool = false, queued: Bool = false, blocked: Bool = false, action: String = "update") -> Execution {
        Execution(
            id: UUID().uuidString, actionID: action, actionTitle: "Update", startedAt: start,
            finishedAt: finished ? start.addingTimeInterval(seconds) : nil, exitCode: exit, isFinished: finished,
            isQueued: queued, timedOut: timedOut, blocked: blocked
        )
    }

    @Test func states() {
        #expect(run(finished: false).state == .running)
        #expect(run(finished: false, queued: true).state == .queued)
        #expect(run(finished: true).state == .succeeded)
        #expect(run(finished: true, exit: 2).state == .failed)
        #expect(run(finished: true, exit: -1, timedOut: true).state == .timedOut)
        #expect(run(finished: true, blocked: true).state == .blocked)
        #expect(run(finished: false).isActive)
        #expect(!run(finished: true).isActive)
    }

    @Test func elapsedStopsWhenFinished() {
        #expect(run(finished: false).elapsed(at: start.addingTimeInterval(42)) == 42)
        #expect(run(finished: true, seconds: 30).elapsed(at: start.addingTimeInterval(500)) == 30)
        #expect(Execution(id: "x", actionID: "a", actionTitle: "A").elapsed(at: start) == nil)
    }

    @Test func noticeForFailuresAndLongRuns() {
        #expect(run(finished: true, exit: 1, seconds: 2).deservesNotice())
        #expect(run(finished: true, seconds: 60).deservesNotice())
        #expect(!run(finished: true, seconds: 5).deservesNotice())
        #expect(!run(finished: false).deservesNotice())
    }

    @Test func tailSkipsEmptyLines() {
        var execution = run(finished: false)
        execution.output = "one\n\ntwo\nthree\n"
        #expect(execution.tail(2) == ["two", "three"])
        let ansible = Execution(id: "y", actionID: "a", actionTitle: "A", startedAt: .now,
                                output: "Pule ZFS ------------------ 0.30s\n\u{1B}[0;32mok: [pve]\u{1B}[0m\n  _ ''\n***********\n")
        #expect(ansible.tail(3) == ["Pule ZFS · 0.30s", "ok: [pve]"])
    }

    @Test func estimateIsTheMedianOfSuccessfulRuns() throws {
        let history = [
            run(finished: true, seconds: 100), run(finished: true, seconds: 300), run(finished: true, seconds: 200),
            run(finished: true, exit: 1, seconds: 5), run(finished: true, seconds: 9, action: "other"), run(finished: false),
        ]
        let estimate = try #require(RunEstimate(history: history, actionID: "update"))
        #expect(estimate.typical == 200)
        #expect(estimate.progress(elapsed: 100) == 0.5)
        #expect(estimate.progress(elapsed: 1_000) == 0.95)
        #expect(estimate.remaining(elapsed: 150) == 50)
        #expect(estimate.remaining(elapsed: 250) == nil)
    }

    @Test func noEstimateWithoutHistory() {
        #expect(RunEstimate(history: [run(finished: true, exit: 1)], actionID: "update") == nil)
        #expect(RunEstimate(history: [run(finished: true, seconds: 50), run(finished: true, seconds: 70)], actionID: "update")?.typical == 60)
    }
}

@Suite struct MachineTests {
    @Test func readsTheWebLampFields() {
        let machine = Machine(key: "0", title: "nas", fields: ["state": "warn", "label": "reboot", "meta": "3 updates", "kind": "vm"])
        #expect(machine == Machine(id: "0", name: "nas", kind: "vm", health: .attention, note: "3 updates"))
    }

    @Test func okLabelIsNoNote() {
        let machine = Machine(key: "1", title: "router", fields: ["state": "ok", "label": "OK", "meta": ""])
        #expect(machine.note == nil)
        #expect(machine.health == .ok)
    }

    @Test func unknownWithoutFields() {
        let machine = Machine(key: "k", title: "media", fields: [:])
        #expect(machine.health == .unknown)
        #expect(machine.name == "media")
        #expect(Machine(key: "k", title: "t", fields: ["state": "DOWN"]).health == .failing)
        #expect(Machine(key: "k", title: "t", fields: ["state": "warn", "meta": "", "summary": "2 aktualizacje", "label": "UWAGA"]).note == "2 aktualizacje")
        #expect(Machine(key: "k", title: "t", fields: ["state": "ok", "summary": "wszystko w porządku"]).note == nil)
        #expect(Machine(key: "k", title: "t", fields: ["state": "stopped"]).health == .off)
    }

    @Test func signedInMeansAKnownUser() {
        func info(_ user: String) -> ServerInfo {
            ServerInfo(title: "", version: "", user: user, loginRequired: true, offersLocalLogin: false, oAuthProviders: [], rootDashboards: [])
        }
        #expect(info("damian").isSignedIn)
        #expect(!info("").isSignedIn)
        #expect(!info("guest").isSignedIn)
    }
}
