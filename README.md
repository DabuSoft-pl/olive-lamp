# Lamp for Mac

Your OliveTin in the menu bar: the state of your machines, your actions in their groups, the log of a running action
and a notification when it ends. The native sibling of [Lamp](https://github.com/DabuSoft-pl/olivetin-lamp), the web
interface for OliveTin.

Early work in progress.

- **Actions that change something run only after you hold them.** Lamp sends OliveTin's named confirmation for you
  once you held the button, as the web Lamp does. Stop is a hold too.
- **A running action reads like an instrument:** elapsed time, how long it usually takes, the last lines of its log.
- **Signs in the way your server expects:** nothing at all behind Tailscale Serve or for guests, an OliveTin API key,
  or your own headers (a JWT, a Cloudflare Access service token). Web sign-in comes next.
- **Nothing leaves your Mac** except requests to the servers you add. Secrets stay in your Keychain.

Machines come from OliveTin entities with the fields the web Lamp's status playbook writes (`state`, `meta` or
`label`, `kind`).

## Build

Needs Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
make test
make run
```

## License

MIT
