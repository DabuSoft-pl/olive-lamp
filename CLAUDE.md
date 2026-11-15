# CLAUDE.md

Lamp for Mac — a macOS menu bar app for OliveTin: the state of your machines, actions in groups, a running action's
log, a notification when it ends. The native sibling of the web Lamp (`~/Projekty/olivetin-lamp`,
github.com/DabuSoft-pl/olivetin-lamp). Swift 6 (strict concurrency), SwiftUI `MenuBarExtra`, macOS 26+, MIT. UI is
English with a Polish translation (String Catalog `Lamp/Localizable.xcstrings`); code, commits and docs are English.
Working name; the repo is local only until the name is settled.

## Architecture (Clean Architecture, as in Tendbar)

```
Domain  <-  Application  <-  Infrastructure
   ^             ^                 ^
   +-------------+---- App: Presentation, Platform, composition root (App/AppContainer)
```

- `LampDomain` — values and rules, no I/O: `Server`, `SignInMethod`, `Credential`, `ServerInfo`, `Action` (hold when it
  has a `confirmation` argument; launch direct, pick from one list of choices, or in the browser), `Execution` (state,
  elapsed, `deservesNotice`), `RunEstimate` (median of the last successful runs), `Machine` (the web Lamp's entity
  fields `state`, `meta`/`label`, `kind`).
- `LampApplication` — use cases (`ProbeServer`, `AddServer`, `RefreshOverview`, `RunAction` with `follow`, `StopRun`),
  `ServerDirectory` (servers, selection, gateways) and the ports: `OliveTinGateway`, `GatewayMaking`, `ServerRepository`,
  `CredentialStore`, `Clock`, outputs `OverviewOutput`, `RunOutput`, `RunNotifying`. `GatewayError` sorts every failure
  into unreachable, sign-in needed, not OliveTin, refused.
- `LampInfrastructure` — `ConnectClient` (Connect RPC: `POST` JSON to `/api/olivetin.api.v1.OliveTinApiService/<Method>`,
  no redirects followed, no cookie store; the credential becomes `Authorization: Bearer`, chosen headers or a `Cookie`
  line), `Wire.swift` (protobuf JSON, lowerCamelCase, defaults omitted, so every field is optional), `OliveTinTime`
  (server-local "2006-01-02 15:04:05", "0001…" means not yet), `HTTPOliveTinGateway`, `KeychainCredentialStore`,
  `JSONServerRepository` (`~/Library/Application Support/Lamp/servers.json`, 0700/0600, never secrets), `SystemClock`.
- `Lamp/App` — `LampApp`, `AppContainer` (refreshes now and every 60 s), `Snapshot` (Debug only:
  `Lamp.app/Contents/MacOS/Lamp -snapshot <folder>` renders the panel in both appearances to PNG).
- `Lamp/Platform` — `Preferences` (UserDefaults), `UserNotificationsAdapter`, `StatusItemMenu` (right click on the lamp: refresh, browser, servers, Settings, Quit).
- `Lamp/Presentation` — `Panel` (view model implements the output ports, controller turns intent into use cases),
  `Servers` (Settings and the add-server sheet), `Shared` (`Palette`, `Clockface`, `HoldRing`, `HoldToRun`, `LampMark`).

## Rules

- Nothing leaves the Mac except requests to the OliveTin servers the user added. No analytics.
- Secrets (API keys, headers, session cookies) live only in the Keychain, one item per server.
- Never follow a redirect with the user's credential: a redirect means a proxy wants a sign-in.
- OliveTin's named confirmation is sent as "1" only after the user held the action (it guards against accidents, not
  access). Stop is a hold too.
- Design: docs/design (copy of the mockups). Neutral system chrome, one accent: the lamp's amber `#f2a541`
  (`Palette.amberInk` for text). Green and red only for states. 4 pt grid; text 11, 12, 13, 15.
- User-facing strings are English literals; add the Polish translation of every new or changed string to
  `Localizable.xcstrings` (xcodebuild does not sync the catalog; the keys are in `build/**/*.stringsdata`).

## Commands

```bash
make test        # Domain, Application and Infrastructure tests
make test-live   # also against the web Lamp's mock: `PORT=8080 node dev/server.mjs` in olivetin-lamp first
make build       # xcodegen + xcodebuild (Debug, ad-hoc signed) into build/
make run         # build and open the app
```

## Next

Web sign-in (a `WKWebView` sheet that keeps the domain's cookies), app icon (`tools/make-icon.swift`, as in Tendbar),
launch at login, Sparkle, notarized release, Homebrew. Plan: `~/Projekty/vault/Projekty/Lamp na Maca/`.
