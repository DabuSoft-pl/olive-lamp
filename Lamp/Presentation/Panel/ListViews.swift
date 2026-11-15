import LampApplication
import LampDomain
import SwiftUI

/// The entities of one OliveTin type, each with a state dot. The heading picks the type, or hides the list.
struct MachineList: View {
    let machines: [Machine]
    let types: [String]
    /// nil: the list is hidden.
    let type: String?
    let model: PanelViewModel
    let controller: PanelController
    @State private var opened: Machine.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
                .padding(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            if type != nil {
                // Two columns keep a homelab's worth of machines on one screen; a long name ends in "…" and shows in full on hover.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], alignment: .leading, spacing: 0) {
                    ForEach(machines) { machine in
                        cell(machine)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var heading: some View {
        Menu {
            ForEach(types, id: \.self) { item in
                Toggle(Self.title(of: item), isOn: Binding(get: { item == type }, set: { _ in controller.showEntities(item) }))
            }
            Divider()
            Toggle("Hide", isOn: Binding(get: { type == nil }, set: { _ in controller.showEntities("") }))
        } label: {
            HStack(spacing: 4) {
                Text(type.map(Self.title(of:)) ?? String(localized: "Entities"))
                Image(systemName: type == nil ? "chevron.right" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose which OliveTin entities to show")
    }

    /// `machine` is the web Lamp's own type; any other type keeps the name its config gives it.
    static func title(of type: String) -> String {
        type == "machine" ? String(localized: "Machines") : type.prefix(1).uppercased() + type.dropFirst()
    }

    /// A click shows what OliveTin offers for the machine.
    private func cell(_ machine: Machine) -> some View {
        Button { opened = machine.id } label: { label(machine) }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(get: { opened == machine.id }, set: { if !$0 { opened = nil } }), arrowEdge: .bottom) {
                MachineActions(machine: machine, model: model, controller: controller)
            }
    }

    private func label(_ machine: Machine) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color(machine.health)).frame(width: 8, height: 8)
            Text(machine.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                // The name says which one; a long note (Docker's "Exited (128) 13 days ago") gives way first.
                .layoutPriority(1)
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
        .accessibilityHint(Text("Shows its actions"))
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

/// The actions of one machine, read when its popover opens. It closes once one of them starts, so the run shows in
/// the panel.
private struct MachineActions: View {
    let machine: Machine
    let model: PanelViewModel
    let controller: PanelController
    @State private var actions: [Action]?
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(machine.name)
                .font(.system(size: 13, weight: .semibold))
                .padding(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            if let actions, !actions.isEmpty {
                ForEach(actions) { action in
                    ActionRow(action: action, model: model, controller: controller)
                }
            } else {
                Group {
                    if failed {
                        Text("Could not read its actions")
                    } else if actions == nil {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("No actions for this machine")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(8)
        .frame(width: 320)
        .task {
            let read = await controller.actions(of: machine)
            failed = read == nil
            actions = read ?? []
        }
        .onChange(of: model.run?.execution.id) { _, started in
            if started != nil { dismiss() }
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
                if groups.count > 3 {
                    // Many dashboards or fieldsets: a menu, since a row of tabs would not fit.
                    Picker("Group", selection: Binding(get: { shown ?? "" }, set: { group = $0 })) {
                        ForEach(groups, id: \.self) { name in Text(name).tag(name) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                } else if groups.count > 1 {
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
            VStack(alignment: .leading, spacing: 0) {
                let visible = actions.filter { shown == nil || ($0.group ?? Self.ungrouped) == shown }
                let openers = Self.sectionOpeners(in: visible)
                ForEach(visible) { action in
                    VStack(alignment: .leading, spacing: 0) {
                        // With several dashboards, a fieldset reads as a heading over its actions.
                        if let section = action.section, openers.contains(action.id) {
                            Text(section)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(EdgeInsets(top: action.id == visible.first?.id ? 4 : 12, leading: 8, bottom: 2, trailing: 8))
                        }
                        ActionRow(action: action, model: model, controller: controller)
                    }
                }
            }
            .padding(EdgeInsets(top: 4, leading: 8, bottom: 8, trailing: 8))
        }
    }

    static let ungrouped = String(localized: "Other")

    /// The actions that start a new section, so each heading shows once.
    static func sectionOpeners(in actions: [Action]) -> Set<String> {
        var openers: Set<String> = []
        var previous: String??
        for action in actions where previous != .some(action.section) {
            openers.insert(action.id)
            previous = .some(action.section)
        }
        return openers
    }

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
        let waitsForReason = action.justification != nil && reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        Group {
            if action.requiresHold, action.launch != .inBrowser {
                row(trigger: AnyView(
                    HoldToRun(enabled: enabled && !waitsForReason, action: { controller.run(action) }) { progress in
                        head(icon: AnyView(HoldRing(progress: progress, tint: Palette.amber)),
                             subtitle: waitsForReason ? String(localized: "Give a reason to run it")
                                : progress > 0 ? String(localized: "Keep holding") : String(localized: "Hold to run"),
                             highlight: progress > 0)
                    }
                    .accessibilityLabel(Text("\(action.title), hold to run"))
                ))
            } else {
                let runnable = (enabled && !waitsForReason) || action.launch == .inBrowser
                row(trigger: AnyView(
                    Button { controller.run(action) } label: {
                        head(icon: AnyView(Image(systemName: action.launch == .inBrowser ? "arrow.up.forward.square" : "play.circle")
                            .font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 16, height: 16)),
                             subtitle: action.launch == .inBrowser ? String(localized: "Opens in the browser")
                                : waitsForReason ? String(localized: "Give a reason to run it") : nil,
                             highlight: false)
                    }
                    .buttonStyle(.plain)
                    .disabled(!runnable)
                ))
            }
        }
        .opacity(enabled || action.launch == .inBrowser ? 1 : 0.5)
        .onHover { hovering = $0 }
    }

    /// `trigger` is the icon and title, held or clicked. The lists and the reason stay outside it: a picker inside a
    /// button's label turns into plain text, and a press in a text field must never count as a hold.
    private func row(trigger: AnyView) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                trigger
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
                // OliveTin asks for a reason and keeps it with the run.
                if action.justification != nil, action.launch != .inBrowser {
                    TextField("Reason", text: reasonBinding, prompt: Text("Why you run it"))
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .padding(.leading, 28)
                }
            }
            if lists.count == 1 { picker(for: lists[0]) }
        }
        .padding(8)
        .frame(minHeight: 44)
        .background(hovering ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 8))
    }

    private var reason: String {
        model.reasons[action.id] ?? action.justification ?? ""
    }

    private var reasonBinding: Binding<String> {
        Binding(get: { reason }, set: { model.reasons[action.id] = $0 })
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
