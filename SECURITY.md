# Security

Olive Lamp holds sign-in secrets for your OliveTin servers (API keys, headers, session cookies) and runs actions on
them, so mistakes here matter. Please report a security problem privately through
[GitHub's private vulnerability reporting](https://github.com/DabuSoft-pl/olive-lamp/security/advisories/new), not in a
public issue.

Useful to include: the Olive Lamp version, what an attacker needs (a web page you open, another app or user on the
Mac, a malicious OliveTin server or proxy…) and what they gain.

Examples of what counts:

- a secret leaving the Keychain, reaching disk or a log, or being sent to another host (a redirect, a cleartext hop)
- an `olivelamp://` link starting an action without the token from `actions.json`, or a hold action without
  confirmation
- `servers.json` or `actions.json` readable or writable by other users
- an update installed without a valid Sparkle signature

Problems in OliveTin itself go to [OliveTin](https://github.com/OliveTin/OliveTin/security).

Only the latest version gets fixes.
