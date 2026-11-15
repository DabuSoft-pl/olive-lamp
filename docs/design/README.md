# Design

Mockups of the first version, drawn on a Claude design canvas:
https://claude.ai/artifact/6PKmR1im4tTUZKyBfu5tuU (private to the owner).

The `.dc.html` files here are a copy of that canvas (2026-11-15), so the design survives without the link. Each is
one artboard; `canvas.json` places them.

| File | Screen |
|---|---|
| `Main.dc.html` | Menu bar panel: server, running action, machines, actions in groups |
| `MainLight.dc.html` | The same panel in the light appearance |
| `Run.dc.html` | A running action: elapsed time, estimate from the last run, log, hold to stop |
| `SignIn.dc.html` | Adding a server: detection, then web sign-in, API key or headers |
| `States.dc.html` | Menu bar states, notifications and the app icon |

## Direction

- World: a desk lamp at night. Neutral graphite chrome in both appearances; the only accent is the amber of the
  lamp's light, `#f2a541` (as text on light surfaces `#9a5806`). Green and red only mean a state.
- The moment: the running action reads like an instrument (time, progress against the last run, log tail).
- The signature: a ring that fills while you hold, on every action that changes something, Stop included.
- Type: Geist and JetBrains Mono in the web Lamp; the app uses the system font and its monospaced design.
- 4 px grid; text 11, 12, 13 and 15 pt.
