# CLAUDE.md

Olive Lamp — a macOS menu bar app for OliveTin: the state of your machines, actions in groups, a running action's
log, a notification when it ends. The native sibling of the web Lamp (`~/Projekty/olivetin-lamp`,
github.com/DabuSoft-pl/olivetin-lamp). Swift 6 (strict concurrency), SwiftUI `MenuBarExtra`, macOS 26+, MIT. UI is
English with a Polish translation (String Catalog `Lamp/Localizable.xcstrings`); code, commits and docs are English.
Bundle `pl.dabusoft.olivelamp`, product "Olive Lamp.app" (XcodeGen target and scheme `OliveLamp`); sources stay in
`Lamp/` and `Packages/LampKit`. Data: `~/Library/Application Support/Olive Lamp/servers.json`, Keychain service
`pl.dabusoft.olivelamp.credentials`. Repo github.com/DabuSoft-pl/olive-lamp (private for now, to be made public).

## Architecture (Clean Architecture, as in Tendbar)

```
Domain  <-  Application  <-  Infrastructure
   ^             ^                 ^
   +-------------+---- App: Presentation, Platform, composition root (App/AppContainer)
```

- `LampDomain` — values and rules, no I/O: `Server`, `SignInMethod`, `Credential`, `ServerInfo`, `Action` (hold when it
  has a `confirmation` argument; launch direct, pick from one list of choices, or in the browser), `Execution` (state,
  elapsed, `deservesNotice`), `RunEstimate` (median of the last successful runs), `Machine` (any OliveTin entity, field
  names matched without regard to case: name from `name`/`Names`, state from `state`/`status`, kind from
  `kind`/`type`/`image`; the web Lamp's `meta`/`summary`/`label` and Docker's `Status` as the note), `Server.entityType`
  (nil picks `machine` or the first type with entities, "" hides the list).
- `LampApplication` — use cases (`ProbeServer`, `AddServer`, `SignInAgain`, `RefreshOverview`, `RunAction` with
  `follow`, `StopRun`, `ChooseEntities`), `RunRequest` (an `olivelamp://run` link: token check, hold needs
  `confirmed=1`, picks must be offered choices) and the `ActionCatalog` port,
  `ServerDirectory` (servers, selection, gateways) and the ports: `OliveTinGateway`, `GatewayMaking`, `ServerRepository`,
  `CredentialStore`, `Clock`, outputs `OverviewOutput`, `RunOutput`, `RunNotifying`. `GatewayError` sorts every failure
  into unreachable, sign-in needed, not OliveTin, refused.
- `LampInfrastructure` — `ConnectClient` (Connect RPC: `POST` JSON to `/api/olivetin.api.v1.OliveTinApiService/<Method>`,
  no redirects followed, no cookie store; the credential becomes `Authorization: Bearer`, chosen headers or a `Cookie`
  line), `Wire.swift` (protobuf JSON, lowerCamelCase, defaults omitted, so every field is optional), `OliveTinTime`
  (server-local "2006-01-02 15:04:05", "0001…" means not yet), `HTTPOliveTinGateway`, `KeychainCredentialStore`,
  `JSONServerRepository` (`~/Library/Application Support/Olive Lamp/servers.json`, 0700/0600, never secrets),
  `JSONActionCatalog` (`actions.json` beside it, 0600: the shown server's actions and the link token, for Raycast),
  `SystemClock`.
- `Lamp/App` — `LampApp`, `AppContainer` (refreshes now and every 60 s), `Snapshot` (Debug only:
  `"Olive Lamp.app/Contents/MacOS/Olive Lamp" -snapshot <folder>` renders the panel against the saved servers),
  `Screenshots` (Debug only, `make screenshots`: README images from made-up data, through real AppKit windows).
- `Lamp/Platform` — `Preferences` (UserDefaults), `UserNotificationsAdapter`, `StatusItemMenu` (right click on the lamp:
  refresh, browser, servers, Settings, updates, Quit), `SoftwareUpdate` (Sparkle, feed on the latest GitHub release,
  EdDSA key in the keychain as account `olivelamp`), `LinkReceiver` (`olivelamp://` Apple events), `LaunchAtLogin`.
- `raycast/` — the Raycast extension (TypeScript): reads `actions.json`, asks before a hold action, opens
  `olivelamp://run?token=…&server=…&action=…[&confirmed=1][&reason=…][&arg.<name>=…]`. `npm install && npm run build`.
- `Lamp/Presentation` — `Panel` (view model implements the output ports, controller turns intent into use cases),
  `Servers` (Settings and the add-server sheet), `Shared` (`Palette`, `Clockface`, `HoldRing`, `HoldToRun`, `LampMark`).

## Rules

- Nothing leaves the Mac except requests to the OliveTin servers the user added and Sparkle reading the appcast on
  GitHub (can be turned off). No analytics.
- A link runs an action only with the catalog's token: any web page can open `olivelamp://`.
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
make test-auth   # every sign-in method against dev/auth (a local OliveTin: API key, trusted header, JWT cookie, local user)
make test-live   # also against the web Lamp's mock: `PORT=8080 node dev/server.mjs` in olivetin-lamp first
make build       # xcodegen + xcodebuild (Debug, ad-hoc signed) into build/
make run         # build and open the app
make screenshots # README images in docs/images
make release     # notarized DMG, appcast.xml and Sparkle deltas in build/release (team ZFG7SZ938C, notarytool profile dabusoft)
```

Releases go on GitHub Releases (DMG, .sha256, appcast.xml, every .delta); raise MARKETING_VERSION and
CURRENT_PROJECT_VERSION first, then update `Casks/olive-lamp.rb` in `~/Projekty/homebrew-tap`. Sparkle and Homebrew
need the repo public.

## App icon

`Lamp/Assets.xcassets/AppIcon.appiconset` is generated: `swift tools/make-icon.swift Lamp/Assets.xcassets/AppIcon.appiconset
/tmp/preview.png` redraws every size from the mockup in docs/design/States.dc.html (a metal desk lamp lighting a small
server; 64 px and below drop the fine detail). macOS shows it in notifications, so there is no separate notification
logo. The menu bar mark stays a template symbol on purpose.

## Next

1.0.1: the SwiftUI review fixes; related actions per machine; App Intents. Plan: `~/Projekty/vault/Projekty/Olive Lamp/`.
