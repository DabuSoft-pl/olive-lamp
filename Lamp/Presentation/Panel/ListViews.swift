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
            ForEach(machines) { machine in
                HStack(spacing: 8) {
                    Circle().fill(color(machine.health)).frame(width: 8, height: 8)
                    Text(machine.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        .frame(width: 148, alignment: .leading)
                    if let kind = machine.kind {
                        Text(kind).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if let note = machine.note {
                        Text(note)
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(noteStyle(machine.health))
                            .lineLimit(1)
                    }
                }
                .frame(height: 36)
                .padding(.horizontal, 16)
                .accessibilityElement(children: .combine)
                .accessibilityValue(Text(healthText(machine.health)))
            }
        }
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
        let shown = groups.count > 1 ? (group ?? groups.first ?? "") : nil
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
                    row(icon: AnyView(HoldRing(progress: progress, tint: Palette.amber)), subtitle: progress > 0 ? String(localized: "Keep holding") : String(localized: "Hold to run"), highlight: progress > 0)
                }
                .accessibilityLabel(Text("\(action.title), hold to run"))
            } else {
                Button {
                    controller.run(action)
                } label: {
                    row(icon: AnyView(Image(systemName: action.launch == .inBrowser ? "arrow.up.forward.square" : "play.circle")
                        .font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 16, height: 16)),
                        subtitle: action.launch == .inBrowser ? String(localized: "Opens in the browser") : nil, highlight: false)
                }
                .buttonStyle(.plain)
                .disabled(!enabled && action.launch != .inBrowser)
            }
        }
        .opacity(enabled || action.launch == .inBrowser ? 1 : 0.5)
        .onHover { hovering = $0 }
    }

    private func row(icon: AnyView, subtitle: String?, highlight: Bool) -> some View {
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
            if case .pick(let argument) = action.launch, case .choice(let choices) = argument.kind {
                Picker(argument.title, selection: pickBinding(default: choices.first?.value ?? "")) {
                    ForEach(choices) { choice in Text(choice.title).tag(choice.value) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            }
        }
        .padding(8)
        .frame(minHeight: 44)
        .background(hovering || highlight ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private func pickBinding(default value: String) -> Binding<String> {
        Binding(
            get: { model.picks[action.id] ?? value },
            set: { model.picks[action.id] = $0 }
        )
    }
}
