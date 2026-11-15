import LampApplication
import LampDomain
import SwiftUI
import WebKit

/// The server's own sign-in page in a sheet: a username and password, OAuth, or the proxy in front of it. Once the
/// page has signed the user in, Lamp keeps that domain's cookies, and only those, in the Keychain. See
/// docs/design/SignIn.dc.html.
struct WebSignInView: View {
    let address: URL
    /// Asks the server who the cookies belong to.
    let check: (Credential) async throws(GatewayError) -> ServerInfo
    let signedIn: (Credential, ServerInfo) -> Void
    @Environment(\.dismiss) private var dismiss
    /// Private to this sheet: nothing from it outlives the sign-in except the cookies Lamp keeps.
    @State private var store = WKWebsiteDataStore.nonPersistent()
    @State private var page: WebPage?
    @State private var status = String(localized: "Sign in as you do in the browser")
    @State private var checking = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "lock").foregroundStyle(.secondary)
                Text(page?.url?.host() ?? address.host() ?? address.absoluteString)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if page?.isLoading == true { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 16)
            .frame(height: 36)
            Divider()
            if let page {
                WebView(page)
            } else {
                Color.clear
            }
            Divider()
            HStack(spacing: 8) {
                Text(status).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("I'm Signed In") { Task { await take(reportingGuest: true) } }
                    .disabled(checking)
            }
            .padding(16)
        }
        .frame(width: 560, height: 640)
        .task {
            var configuration = WebPage.Configuration()
            configuration.websiteDataStore = store
            let page = WebPage(configuration: configuration)
            self.page = page
            _ = page.load(URLRequest(url: address))
            // Every page that finishes loading may be the one after a successful sign-in. A failed navigation ends
            // the stream (an OAuth provider cancelling a redirect, say), so listening starts again.
            while !Task.isCancelled {
                do {
                    for try await event in page.navigations where event == .finished {
                        await take(reportingGuest: false)
                    }
                } catch {}
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    /// Tries the cookies the page holds for the server's domain. Quietly, after each page; with a word when asked.
    private func take(reportingGuest: Bool) async {
        guard !checking else { return }
        guard let credential = SessionCookies.credential(from: await store.httpCookieStore.allCookies(), for: address) else {
            if reportingGuest { status = String(localized: "The server has not given Lamp a session yet") }
            return
        }
        checking = true
        defer { checking = false }
        do {
            let info = try await check(credential)
            if info.isSignedIn {
                signedIn(credential, info)
                dismiss()
            } else if reportingGuest {
                status = String(localized: "The server still sees a guest. Finish signing in on the page")
            }
        } catch {
            if reportingGuest { status = ProblemText.of(error) }
        }
    }

}
