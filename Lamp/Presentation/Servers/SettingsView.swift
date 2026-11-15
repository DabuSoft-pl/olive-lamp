import LampApplication
import LampDomain
import SwiftUI

struct SettingsView: View {
    let servers: ServersController
    @Bindable var preferences: Preferences
    let launchAtLogin: LaunchAtLogin
    @State private var list: [Server] = []
    @State private var adding = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Servers") {
                if list.isEmpty {
                    Text("No server yet").foregroundStyle(.secondary)
                }
                ForEach(list) { server in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name)
                            Text(server.address.absoluteString)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(SignInText.of(server.signIn)).foregroundStyle(.secondary)
                        Button("Remove", role: .destructive) {
                            servers.remove(server)
                            list = servers.servers
                        }
                        .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Spacer()
                    Button("Add Server…") { adding = true }
                }
            }
            Section("Notifications") {
                Toggle("Tell me when an action I started fails or ends after a long run", isOn: $preferences.notifyWhenDone)
            }
            Section {
                Toggle("Open at login", isOn: Binding(get: { launchAtLogin.isOn }, set: { launchAtLogin.set($0) }))
            } footer: {
                if launchAtLogin.state == .requiresApproval {
                    Text("Allow Lamp in System Settings → General → Login Items").foregroundStyle(.secondary)
                } else if let error = launchAtLogin.error {
                    Text(error).foregroundStyle(Palette.bad)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .frame(minHeight: 320)
        .onAppear {
            list = servers.servers
            launchAtLogin.refresh()
        }
        // Esc closes Settings, as it closes the add-server sheet; the sheet takes it first while it is open.
        .background {
            Button("Close", action: { dismiss() })
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
        .sheet(isPresented: $adding, onDismiss: { list = servers.servers }) {
            AddServerView(servers: servers)
        }
    }
}

enum SignInText {
    static func of(_ method: SignInMethod) -> String {
        switch method {
        case .automatic: String(localized: "Automatic")
        case .apiKey: String(localized: "API key")
        case .headers: String(localized: "Headers")
        case .webSession: String(localized: "Web sign-in")
        }
    }
}

/// See docs/design/SignIn.dc.html. Web sign-in comes in a later version.
struct AddServerView: View {
    let servers: ServersController
    @Environment(\.dismiss) private var dismiss
    @State private var addressText = ""
    @State private var name = ""
    @State private var method: SignInMethod = .automatic
    @State private var apiKey = ""
    @State private var headers: [HeaderRow] = [HeaderRow(), HeaderRow()]
    @State private var status: Status = .idle

    enum Status: Equatable {
        case idle, checking
        case found(ServerInfo)
        case problem(String)
    }

    struct HeaderRow: Identifiable, Equatable {
        let id = UUID()
        var name = ""
        var value = ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add a Server").font(.system(size: 15, weight: .semibold))
                Text("Lamp talks only to this address. Keys and headers stay in your Keychain")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(EdgeInsets(top: 20, leading: 20, bottom: 8, trailing: 20))

            Form {
                TextField("OliveTin address", text: $addressText, prompt: Text(verbatim: "https://olivetin.example.com"))
                    .font(.system(size: 13, design: .monospaced))
                    .onChange(of: addressText) { status = .idle }
                TextField("Name", text: $name, prompt: Text("From the server"))
                Picker("Sign in", selection: $method) {
                    Text("Automatic").tag(SignInMethod.automatic)
                    Text("API key").tag(SignInMethod.apiKey)
                    Text("Headers").tag(SignInMethod.headers)
                }
                .onChange(of: method) { status = .idle }
                switch method {
                case .apiKey:
                    SecureField("API key", text: $apiKey)
                case .headers:
                    ForEach($headers) { $row in
                        HStack {
                            TextField("Header", text: $row.name, prompt: Text(verbatim: "CF-Access-Client-Id"))
                            SecureField("Value", text: $row.value)
                        }
                    }
                default:
                    EmptyView()
                }
                Text(help).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)

            statusLine
                .padding(.horizontal, 20)
                .frame(minHeight: 24, alignment: .leading)

            HStack {
                Button("Check") { Task { await check() } }
                    .disabled(address == nil || status == .checking)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Server") { Task { await add() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(address == nil || status == .checking)
            }
            .padding(20)
        }
        .frame(width: 520)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case .found(let info):
            HStack(spacing: 8) {
                Circle().fill(info.loginRequired && !info.isSignedIn ? Palette.amber : Palette.ok).frame(width: 8, height: 8)
                Text(Self.describe(info)).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case .problem(let text):
            Text(text).font(.system(size: 12)).foregroundStyle(Palette.bad)
        }
    }

    private var help: String {
        switch method {
        case .automatic:
            String(localized: "For a server that knows you already, through Tailscale or another proxy, or lets guests in")
        case .apiKey:
            String(localized: "The apiKey of an OliveTin local user. It does not expire")
        case .headers:
            String(localized: "A JWT, or a service token for Cloudflare Access and similar proxies")
        case .webSession:
            ""
        }
    }

    private var address: URL? { ServersController.address(from: addressText) }

    private var credential: Credential? {
        switch method {
        case .automatic, .webSession:
            return nil
        case .apiKey:
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty ? nil : .apiKey(key)
        case .headers:
            var values: [String: String] = [:]
            for row in headers {
                let name = row.name.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { values[name] = row.value }
            }
            return values.isEmpty ? nil : .headers(values)
        }
    }

    private func check() async {
        guard let address else { return }
        status = .checking
        do {
            status = .found(try await servers.check(address: address, credential: credential))
        } catch {
            status = .problem(ProblemText.of(error))
        }
    }

    private func add() async {
        guard let address else { return }
        status = .checking
        do {
            try await servers.add(name: name, address: address, signIn: method, credential: credential)
            dismiss()
        } catch {
            status = .problem(error == .signInNeeded ? String(localized: "The server does not know you yet. Choose an API key or headers") : ProblemText.of(error))
        }
    }

    static func describe(_ info: ServerInfo) -> String {
        let version = info.version.isEmpty ? "OliveTin" : "OliveTin \(info.version)"
        if info.isSignedIn { return String(localized: "\(version) · signed in as \(info.user)") }
        if info.loginRequired { return String(localized: "\(version) · sign-in required") }
        return String(localized: "\(version) · open to guests")
    }
}
