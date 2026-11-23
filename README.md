# AppPresence

Shows the app you are currently using on your Discord profile, with its real icon. A menu bar app, no dock icon, no login, no bot token.

```
aryan
Live App Status
  Rex
```

## How it works

- `NSWorkspace.didActivateApplicationNotification` fires the moment you switch apps.
- The bundle ID maps to a name, and to an icon at `https://cdn.jsdelivr.net/gh/aryanranderiya/app-presence@main/icons/<bundle-id>.png`.
- A single-slot scheduler sends `SET_ACTIVITY` over Discord's local IPC socket. Budget is 5 sends per 20 seconds. Inside the budget the update is immediate. Over it, only the newest app is kept and sent the instant a slot frees.
- Password managers, Messages, Signal and WhatsApp are filtered out before anything is sent.

Verified against a live client: Discord accepts external URLs for `large_image` and rewrites them to `mp:external/...`, so the 300-asset limit does not apply and nothing is uploaded by hand.

## Run

```bash
./scripts/install.sh
```

Builds, codesigns ad-hoc, installs to `~/Applications`, launches. Menu bar item has the on/off toggle, launch at login, and quit.

## Add an app

```bash
swift scripts/export-icons.swift icons   # re-exports every app in /Applications
git add icons && git commit -m "icons" && git push
```

A new app is a new file named after its bundle ID. No code change, no mapping table. Commit and the URL resolves immediately because the path is new.

## Debug

```bash
swift scripts/probe.swift <application-id> <image-url> "Name"
```

Connects to the socket, handshakes, sets an activity, prints Discord's reply, clears it.

## Layout

| Path | Role |
| --- | --- |
| `Sources/AppPresence/main.swift` | Status item, menu, wiring |
| `Sources/AppPresence/FocusMonitor.swift` | Frontmost app changes |
| `Sources/AppPresence/Models.swift` | `AppInfo`, name and icon mapping, privacy filter |
| `Sources/AppPresence/PresenceScheduler.swift` | Rate budget and coalescing |
| `Sources/AppPresence/DiscordRPC.swift` | Unix socket, framing, reconnect |
| `scripts/export-icons.swift` | 512px PNG export from installed apps |
| `scripts/probe.swift` | Manual RPC probe for debugging |
