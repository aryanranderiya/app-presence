import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = Store.shared
    private let registry = AppRegistry()
    private let monitor = FocusMonitor()
    private let scheduler = PresenceScheduler()
    private let rpc = DiscordRPC(clientID: "1574409162891460719")
    private let settingsWindow = SettingsWindowController()

    private var waka: WakaTimeService?
    private var wakaSignature = ""
    private var contextTimer: Timer?
    private var statusItem: NSStatusItem?
    private var currentItem: NSMenuItem?
    private var enabledItem: NSMenuItem?
    private var launchItem: NSMenuItem?
    private var current: AppInfo?
    private var enabled = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        enabled = store.setting("enabled") == "1"
        buildStatusItem()
        scheduler.onSend = { [weak self] presence in self?.rpc.setActivity(presence) }
        scheduler.onClear = { [weak self] in self?.rpc.clearActivity() }
        monitor.onAppChange = { [weak self] app in self?.route(app) }
        AppContext.onChange = { [weak self] bundleID in
            guard let self, self.enabled,
                  let app = self.monitor.current(), app.bundleID == bundleID
            else { return }
            self.refreshContext()
        }
        rpc.connect()
        monitor.start()
        syncWakaTime()

        contextTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshContext()
        }

        if CommandLine.arguments.contains("--settings") || store.allowedCount() == 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.openSettings()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        contextTimer?.invalidate()
        monitor.stop()
        waka?.shutdown()
        rpc.shutdown()
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = MenuBarIcon.make()
        item.button?.image = icon
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.toolTip = "AppPresence"

        let menu = NSMenu()
        menu.delegate = self

        let current = menuItem("No app", nil)
        current.isEnabled = false
        currentItem = current
        menu.addItem(current)
        menu.addItem(.separator())

        let toggle = menuItem("Enabled", #selector(toggleEnabled))
        toggle.state = enabled ? .on : .off
        enabledItem = toggle
        menu.addItem(toggle)

        let launch = menuItem("Launch at Login", #selector(toggleLaunchAtLogin))
        launch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        launchItem = launch
        menu.addItem(launch)

        let settings = menuItem("Settings…", #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)

        menu.addItem(.separator())
        let quitItem = menuItem("Quit", #selector(quit))
        quitItem.keyEquivalent = "q"
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    private func menuItem(_ title: String, _ action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        currentItem?.title = label(for: current)
    }

    private func label(for app: AppInfo?) -> String {
        guard let app else { return "No app" }
        return app.elapsed.isEmpty ? app.name : "\(app.name) · \(app.elapsed)"
    }

    private func route(_ app: AppInfo) {
        guard let resolved = registry.resolve(app) else {
            if current == nil { currentItem?.title = "No app" }
            return
        }
        current = resolved
        currentItem?.title = label(for: resolved)
        scheduler.submit(registry.presence(for: resolved))
    }

    private func refreshContext() {
        guard enabled, let app = monitor.current(), let resolved = registry.resolve(app) else { return }
        scheduler.submit(registry.presence(for: resolved))
    }

    private func syncWakaTime() {
        let on = store.setting("wakatime_enabled") == "1"
        let id = store.setting("wakatime_client_id") ?? ""
        let signature = "\(on)#\(id)"
        guard signature != wakaSignature else { return }
        wakaSignature = signature
        waka?.shutdown()
        waka = nil
        guard on, !id.isEmpty else { return }
        let client = DiscordRPC(clientID: id)
        client.connect()
        let service = WakaTimeService(rpc: client, store: store)
        service.start()
        waka = service
    }

    private func settingsChanged() {
        enabled = store.setting("enabled") == "1"
        enabledItem?.state = enabled ? .on : .off

        if let shown = current, store.policy(for: shown.bundleID) != .show {
            scheduler.clear()
            current = nil
            currentItem?.title = "No app"
        }
        if enabled, let app = monitor.current() { route(app) }
        syncWakaTime()
    }

    @objc private func openSettings() {
        settingsWindow.show { [weak self] in self?.settingsChanged() }
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        store.setSetting("enabled", enabled ? "1" : "0")
        enabledItem?.state = enabled ? .on : .off
        scheduler.setEnabled(enabled)
        if enabled, let app = monitor.current() { route(app) }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            log("launch at login failed: \(error.localizedDescription)")
        }
        launchItem?.state = service.status == .enabled ? .on : .off
        log("launch at login status \(service.status.rawValue)")
    }

    @objc private func quit() {
        waka?.shutdown()
        rpc.shutdown { NSApplication.shared.terminate(nil) }
    }
}

let application = NSApplication.shared

if let index = CommandLine.arguments.firstIndex(of: "--dump-icon"), index + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[index + 1]
    let icon = MenuBarIcon.make()
    let canvas = NSImage(size: icon.size)
    canvas.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: icon.size).fill()
    icon.draw(in: NSRect(origin: .zero, size: icon.size))
    canvas.unlockFocus()
    if let tiff = canvas.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
    }
    exit(0)
}

let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
