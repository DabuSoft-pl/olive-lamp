import LampApplication
import LampDomain
import SwiftUI

/// The window under the menu bar mark. See docs/design/Main.dc.html.
struct PanelView: View {
    let model: PanelViewModel
    let actions: PanelController
    let preferences: Preferences
    /// Off only for snapshots: ImageRenderer draws nothing inside a ScrollView.
    var scrolls = true
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    /// The menu bar window keeps the last offset, or lands at the bottom; every opening starts at the top.
    @State private var scroll = ScrollPosition(edge: .top)
    /// The lists' own height: the menu bar window gives a ScrollView no height of its own, so it would shrink to nothing.
    @State private var listsHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.showingLog, let run = model.run {
                RunLogView(run: run, model: model, actions: actions, preferences: preferences)
            } else {
                header
                content
                footer
            }
        }
        .frame(width: 440)
        .onAppear {
            scroll.scrollTo(edge: .top)
            actions.panelOpened()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(model.servers) { server in
                    Button {
                        actions.select(server)
                    } label: {
                        if server.id == model.selectedServer {
                            Label(server.name, systemImage: "checkmark")
                        } else {
                            Text(server.name)
                        }
                    }
                }
                Divider()
                Button("Add Server…") { SettingsWindow.open(with: openSettings, closing: dismiss) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(serverName).font(.system(size: 15, weight: .semibold))
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    if let subtitle {
                        Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(Text("Server: \(serverName)"))
            Spacer()
            Button {
                actions.refresh()
            } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 13))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh")
            .accessibilityLabel("Refresh")
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 12))
    }

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(24)
        case .noServer:
            EmptyServers { SettingsWindow.open(with: openSettings, closing: dismiss) }
        case .problem(let problem, _):
            ProblemBanner(problem: problem, retry: actions.refresh) { SettingsWindow.open(with: openSettings, closing: dismiss) }
            if let overview = model.overview { body(of: overview) }
        case .overview(let overview):
            body(of: overview)
        }
    }

    @ViewBuilder
    private func body(of overview: Overview) -> some View {
        if let run = model.run {
            RunCard(run: run, model: model, actions: actions)
                .padding(.horizontal, 8)
        }
        if let problem = model.startProblem {
            Text(problem)
                .font(.system(size: 12))
                .foregroundStyle(Palette.bad)
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
        if scrolls {
            ScrollView {
                lists(of: overview)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listsHeight = $0 }
            }
                .scrollPosition($scroll)
                .defaultScrollAnchor(.top)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(max(listsHeight, 120), Self.listHeight))
        } else {
            lists(of: overview)
        }
    }

    private func lists(of overview: Overview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !overview.machines.isEmpty {
                MachineList(machines: overview.machines, runningAction: model.run?.execution)
                Divider().padding(.horizontal, 16).padding(.vertical, 8)
            }
            ActionList(actions: overview.actions, model: model, controller: actions)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Open in Browser") { actions.openInBrowser() }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.amberInk)
                .disabled(model.servers.isEmpty)
            Spacer()
            Menu {
                Button("Settings…") { SettingsWindow.open(with: openSettings, closing: dismiss) }
                Divider()
                Button("Quit Olive Lamp") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape").font(.system(size: 13)).frame(width: 28, height: 28)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .foregroundStyle(.secondary)
            .fixedSize()
            .accessibilityLabel("Settings")
        }
        .font(.system(size: 12))
        .padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 12))
        .frame(height: 40)
        .overlay(alignment: .top) { Divider() }
    }

    /// As tall as the screen allows below the menu bar, leaving room for the header, the footer and a margin.
    private static var listHeight: CGFloat {
        // The panel opens under the lamp the user just clicked, so the screen under the pointer is the one it opens on.
        let mouse = NSEvent.mouseLocation
        let screen = (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main)?.visibleFrame.height ?? 800
        return max(360, screen - 160)
    }

    private var serverName: String {
        model.servers.first { $0.id == model.selectedServer }?.name ?? String(localized: "Olive Lamp")
    }

    private var subtitle: String? {
        guard let overview = model.overview else { return nil }
        let user = overview.info.user.isEmpty ? String(localized: "guest") : overview.info.user
        let checked = overview.checkedAt.formatted(.relative(presentation: .named))
        return String(localized: "\(user) · checked \(checked)")
    }
}

private struct EmptyServers: View {
    let add: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No server yet").font(.system(size: 13, weight: .medium))
            Text("Add the address of your OliveTin to see its machines and run its actions from here")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add Server…", action: add)
                .controlSize(.small)
                .padding(.top, 4)
        }
        .padding(16)
    }
}

private struct ProblemBanner: View {
    let problem: GatewayError
    let retry: () -> Void
    let settings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ProblemText.of(problem))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Try Again", action: retry)
                if problem == .signInNeeded { Button("Sign In…", action: settings) }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }
}

enum SettingsWindow {
    @MainActor
    static func open(with openSettings: OpenSettingsAction, closing dismiss: DismissAction? = nil) {
        // The panel steps aside for the window it opened.
        dismiss?()
        NSApp.windows.filter { $0.className.contains("MenuBarExtra") && $0.isVisible }.forEach { $0.close() }
        // The cooperative `activate()` leaves a menu bar app behind the frontmost app, so the window never shows.
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        DispatchQueue.main.async {
            NSApp.windows.first { $0.identifier?.rawValue.contains("Settings") == true }?.makeKeyAndOrderFront(nil)
        }
    }
}
