import LampApplication
import LampDomain
import SwiftUI

struct MachineList: View {
    let machines: [Machine]
    let runningAction: Execution?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Machines")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            // Two columns keep a homelab's worth of machines on one screen; a long name ends in "…" and shows in full on hover.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], alignment: .leading, spacing: 0) {
                ForEach(machines) { machine in
                    cell(machine)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func cell(_ machine: Machine) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color(machine.health)).frame(width: 8, height: 8)
            Text(machine.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            // A machine that needs you shows why; one that is fine shows what it is.
            if let note = machine.note {
                Text(note)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(noteStyle(machine.health))
                    .lineLimit(1)
            } else if let kind = machine.kind {
                Text(kind).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            }
        }
        .frame(height: 28)
        .contentShape(Rectangle())
        .help([machine.name, machine.kind, machine.note].compactMap { $0 }.joined(separator: " · "))
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(healthText(machine.health)))
    }

    private func color(_ health: Machine.Health) -> Color {
        switch health {
        case .ok: Palette.ok
        case .attention: Palette.amber
        case .failing: Palette.bad
        case .off, .unknown: Palette.off
        }
    }

    private func noteStyle(_ health: Machine.Health) -> AnyShapeStyle {
        switch health {
        case .attention: AnyShapeStyle(.primary)
        case .failing: AnyShapeStyle(Palette.bad)
        default: AnyShapeStyle(.secondary)
        }
    }

    private func healthText(_ health: Machine.Health) -> String {
        switch health {
        case .ok: String(localized: "OK")
        case .attention: String(localized: "Needs attention")
        case .failing: String(localized: "Failing")
        case .off: String(localized: "Off")
        case .unknown: String(localized: "Unknown")
        }
    }
}

/// Actions in their dashboard groups. One that changes something runs only after a hold. See Main.dc.html.
struct ActionList: View {
    let actions: [Action]
    let model: PanelViewModel
    let controller: PanelController
    @State private var group: String?

    var body: some View {
        let groups = Self.groups(of: actions)
        // A group picked on another server may not exist here; then the first group shows.
        let shown = groups.count > 1 ? (group.flatMap { groups.contains($0) ? $0 : nil } ?? groups.first) : nil
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("Actions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if groups.count > 1 {
                    ForEach(groups, id: \.self) { name in
                        Button(name) { group = name }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(name == shown ? .primary : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(name == shown ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
                            .accessibilityAddTraits(name == shown ? .isSelected : [])
                    }
                }
            }
            .padding(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 12))
            if actions.isEmpty {
                Text("This server shows you no actions")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
            VStack(spacing: 0) {
                ForEach(actions.filter { shown == nil || ($0.group ?? Self.ungrouped) == shown }) { action in
                    ActionRow(action: action, model: model, controller: controller)
                }
            }
            .padding(EdgeInsets(top: 4, leading: 8, bottom: 8, trailing: 8))
        }
    }

    static let ungrouped = String(localized: "Other")

    static func groups(of actions: [Action]) -> [String] {
        var seen: [String] = []
        for action in actions {
            let name = action.group ?? ungrouped
            if !seen.contains(name) { seen.append(name) }
        }
        return seen
    }
}

private struct ActionRow: View {
    let action: Action
    let model: PanelViewModel
    let controller: PanelController
    @State private var hovering = false

    var body: some View {
        let busy = model.run?.execution.isActive == true
        let enabled = action.canRun && !busy
        Group {
            if action.requiresHold, action.launch != .inBrowser {
                HoldToRun(enabled: enabled, action: { controller.run(action) }) { progress in
                    row(icon: AnyView(HoldRing(progress: progress, tint: Palette.amber)), subtitle: progress > 0 ? String(localized: "Keep holding") : String(localized: "Hold to run"), highlight: progress > 0, tap: nil)
                }
                .accessibilityLabel(Text("\(action.title), hold to run"))
            } else {
                let runnable = enabled || action.launch == .inBrowser
                row(icon: AnyView(Image(systemName: action.launch == .inBrowser ? "arrow.up.forward.square" : "play.circle")
                    .font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 16, height: 16)),
                    subtitle: action.launch == .inBrowser ? String(localized: "Opens in the browser") : nil, highlight: false,
                    tap: runnable ? { controller.run(action) } : nil)
            }
        }
        .opacity(enabled || action.launch == .inBrowser ? 1 : 0.5)
        .onHover { hovering = $0 }
    }

    /// `tap` makes the icon and title a button. The lists stay outside it: a picker inside a button's label turns into
    /// plain text and cannot be opened.
    private func row(icon: AnyView, subtitle: String?, highlight: Bool, tap: (() -> Void)?) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                if let tap {
                    Button(action: tap) { head(icon: icon, subtitle: subtitle, highlight: highlight) }
                        .buttonStyle(.plain)
                } else {
                    head(icon: icon, subtitle: subtitle, highlight: highlight)
                }
                // Several lists sit under the title, each named, since a bare "cold" says nothing.
                if lists.count > 1 {
                    HStack(spacing: 12) {
                        ForEach(lists, id: \.name) { argument in
                            HStack(spacing: 4) {
                                Text(argument.title).font(.system(size: 12)).foregroundStyle(.secondary)
                                picker(for: argument)
                            }
                        }
                    }
                    .padding(.leading, 28)
                }
            }
            if lists.count == 1 { picker(for: lists[0]) }
        }
        .padding(8)
        .frame(minHeight: 44)
        .background(hovering || highlight ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private func head(icon: AnyView, subtitle: String?, highlight: Bool) -> some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title).font(.system(size: 13)).lineLimit(1)
                if action.isRunning {
                    Text("Running").font(.system(size: 12)).foregroundStyle(Palette.amberInk)
                } else if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(highlight ? AnyShapeStyle(Palette.amberInk) : AnyShapeStyle(.secondary))
                }
            }
            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
    }

    private var lists: [ActionArgument] {
        if case .pick(let arguments) = action.launch { arguments } else { [] }
    }

    @ViewBuilder
    private func picker(for argument: ActionArgument) -> some View {
        if case .choice(let choices) = argument.kind {
            Picker(argument.title, selection: pickBinding(for: argument)) {
                ForEach(choices) { choice in Text(choice.title).tag(choice.value) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        }
    }

    private func pickBinding(for argument: ActionArgument) -> Binding<String> {
        Binding(
            get: { model.picks[action.id]?[argument.name] ?? argument.initialChoice ?? "" },
            set: { model.picks[action.id, default: [:]][argument.name] = $0 }
        )
    }
}
