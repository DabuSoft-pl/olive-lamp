import LampApplication
import LampDomain
import SwiftUI

/// The running action, read like an instrument: time, progress against the usual run, the last lines.
struct RunCard: View {
    let run: RunProgress
    let model: PanelViewModel
    let actions: PanelController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            card(now: context.date)
        }
    }

    private func card(now: Date) -> some View {
        let execution = run.execution
        let elapsed = execution.elapsed(at: now) ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StateDot(state: execution.state)
                Text(execution.actionTitle).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer()
                Text(Clockface.duration(elapsed))
                    .font(.system(size: 13, design: .monospaced))
                    .monospacedDigit()
            }
            RunProgressBar(run: run, elapsed: elapsed)
            Text(RunCaption.of(run, elapsed: elapsed))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            let tail = execution.numberedTail(2)
            if let last = tail.last {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(tail) { line in
                        Text(line.text)
                            .foregroundStyle(line.number == last.number ? .secondary : .tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Palette.inset, in: .rect(cornerRadius: 6))
            }
            HStack(spacing: 8) {
                Button("Show Log") { model.showingLog = true }
                if execution.isActive, execution.canKill || execution.state == .running {
                    StopButton(stop: actions.stop)
                } else if !execution.isActive {
                    Button("Dismiss") { model.dismissRun() }
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
    }
}

/// The whole log of the followed run. See docs/design/Run.dc.html.
struct RunLogView: View {
    let run: RunProgress
    let model: PanelViewModel
    let actions: PanelController
    @Bindable var preferences: Preferences

    var body: some View {
        let execution = run.execution
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    model.showingLog = false
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .medium)).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Back")
                Text(execution.actionTitle).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer()
                HStack(spacing: 8) {
                    StateDot(state: execution.state)
                    Text(StateText.of(execution))
                }
                .font(.system(size: 12))
                .foregroundStyle(execution.state == .running ? Palette.amberInk : .secondary)
            }
            .padding(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 16))

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = execution.elapsed(at: context.date) ?? 0
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Clockface.duration(elapsed))
                            .font(.system(size: 28, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                        Spacer()
                        Text(RunCaption.of(run, elapsed: elapsed))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    RunProgressBar(run: run, elapsed: elapsed)
                }
            }
            .padding(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))

            if !execution.user.isEmpty || execution.startedAt != nil {
                HStack(spacing: 4) {
                    if let started = execution.startedAt {
                        Text("Started \(started.formatted(date: .omitted, time: .shortened))")
                    }
                    if !execution.user.isEmpty { Text("by \(execution.user)") }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            LogText(lines: model.logLines)
                .frame(height: 480)
                .background(Palette.inset, in: .rect(cornerRadius: 10))
                .padding(.horizontal, 8)

            HStack(spacing: 8) {
                Toggle("Notify when done", isOn: $preferences.notifyWhenDone)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy Log") { actions.copyLog() }
                if execution.isActive {
                    StopButton(stop: actions.stop)
                }
            }
            .controlSize(.small)
            .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        }
    }
}

/// Ansible-aware colouring, kept to the palette: tasks quiet, `ok` green, `changed` amber, failures red.
private struct LogText: View {
    /// Split once per new output by the view model, not on every redraw.
    let lines: [LogLine]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(lines) { line in
                    Text(line.text.isEmpty ? " " : line.text)
                        .foregroundStyle(Self.color(of: line.text))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .padding(12)
        }
        .defaultScrollAnchor(.bottom)
    }

    static func color(of line: String) -> Color {
        if line.hasPrefix("ok:") { return Palette.ok }
        if line.hasPrefix("changed:") { return Palette.amberInk }
        if line.hasPrefix("fatal:") || line.hasPrefix("failed:") || line.contains("FAILED!") { return Palette.bad }
        if line.hasPrefix("TASK ") || line.hasPrefix("PLAY ") || line.hasPrefix("PLAY RECAP") { return .secondary }
        return .primary
    }
}

private struct RunProgressBar: View {
    let run: RunProgress
    let elapsed: TimeInterval

    var body: some View {
        let execution = run.execution
        let value: Double? = switch execution.state {
        case .succeeded, .failed, .timedOut, .blocked, .stopped: 1
        case .queued: 0
        case .running: run.estimate?.progress(elapsed: elapsed)
        }
        let tint: Color = switch execution.state {
        case .succeeded: Palette.ok
        case .queued, .running: Palette.amber
        case .stopped: Palette.off
        case .failed, .timedOut, .blocked: Palette.bad
        }
        Group {
            if let value {
                Capsule().fill(.quaternary)
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint).scaleEffect(x: value, anchor: .leading)
                    }
                    .frame(height: 4)
                .accessibilityElement()
                .accessibilityLabel("Progress")
                .accessibilityValue(Text(value.formatted(.percent.precision(.fractionLength(0)))))
            } else {
                ProgressView().progressViewStyle(.linear).tint(Palette.amber).controlSize(.small)
            }
        }
    }
}

private struct StopButton: View {
    let stop: () -> Void

    var body: some View {
        HoldToRun(action: stop) { progress in
            HStack(spacing: 8) {
                HoldRing(progress: progress, tint: Palette.bad, size: 14)
                Text("Hold to Stop")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Palette.bad)
            .padding(.horizontal, 8)
            .frame(height: 24)
        }
        .accessibilityLabel("Stop, hold to confirm")
    }
}

struct StateDot: View {
    let state: Execution.State

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch state {
        case .running, .queued: Palette.amber
        case .succeeded: Palette.ok
        case .failed, .timedOut, .blocked: Palette.bad
        case .stopped: Palette.off
        }
    }
}

enum StateText {
    static func of(_ execution: Execution) -> String {
        switch execution.state {
        case .queued: String(localized: "Queued")
        case .running: String(localized: "Running")
        case .succeeded: String(localized: "Finished")
        case .failed: String(localized: "Failed, exit code \(execution.exitCode)")
        case .timedOut: String(localized: "Timed out")
        case .blocked: String(localized: "Blocked")
        case .stopped: String(localized: "Stopped")
        }
    }
}

enum RunCaption {
    static func of(_ run: RunProgress, elapsed: TimeInterval) -> String {
        let execution = run.execution
        if !execution.isActive { return StateText.of(execution) }
        guard let estimate = run.estimate else { return String(localized: "no earlier run to compare with") }
        let usual = Clockface.duration(estimate.typical)
        if let left = estimate.remaining(elapsed: elapsed) {
            return String(localized: "about \(Clockface.duration(left)) left · usually \(usual)")
        }
        return String(localized: "longer than usual (\(usual))")
    }
}
