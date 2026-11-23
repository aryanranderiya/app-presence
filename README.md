# AppPresence

macOS menu bar app that shows the app you are currently using on Discord, with its real icon.

Icons are exported from `/Applications` at 512px and served to Discord as external `large_image` URLs through jsDelivr, so there is no 300-asset limit and nothing to upload by hand.

## Add an app

1. Export its icon: `swift scripts/export-icons.swift icons`
2. Commit and push. The URL is `https://cdn.jsdelivr.net/gh/aryanranderiya/app-presence@main/icons/<bundle-id>.png`

A new app is a new file. No code change, no mapping table.
