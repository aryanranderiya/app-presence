import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let registry = AppRegistry()
    private let monitor = FocusMonitor()
    private let scheduler = PresenceScheduler()
    private let rpc = DiscordRPC()
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem?
    private var currentItem: NSMenuItem?
    private var enabledItem: NSMenuItem?
    private var launchItem: NSMenuItem?
    private var enabled = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        buildStatusItem()
        scheduler.onSend = { [weak self] app in self?.rpc.setActivity(app) }
        scheduler.onClear = { [weak self] in self?.rpc.clearActivity() }
        monitor.onAppChange = { [weak self] app in self?.route(app) }
        rpc.connect()
        monitor.start()
    }
    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        rpc.shutdown()
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "app.fill", accessibilityDescription: "AppPresence") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "AppPresence"
        }
        let menu = NSMenu()
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
    private func route(_ app: AppInfo) {
        if app.bundleID == Bundle.main.bundleIdentifier { return }
        guard let resolved = registry.resolve(app) else {
            currentItem?.title = "Hidden"
            if enabled { scheduler.clear() }
            return
        }
        currentItem?.title = resolved.name
        scheduler.submit(resolved)
    }
    private func resubmitCurrent() {
        guard enabled, let app = monitor.current(), let resolved = registry.resolve(app) else { return }
        currentItem?.title = resolved.name
        scheduler.submit(resolved)
    }
    @objc private func toggleEnabled() {
        enabled.toggle()
        defaults.set(enabled, forKey: "enabled")
        enabledItem?.state = enabled ? .on : .off
        scheduler.setEnabled(enabled)
        if enabled { resubmitCurrent() }
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
        rpc.shutdown { NSApplication.shared.terminate(nil) }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
