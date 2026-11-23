import AppKit

final class FocusMonitor {
    var onAppChange: ((AppInfo) -> Void)?

    private var observer: NSObjectProtocol?
    private var lastKey: String?

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.handle(app)
        }
        if let app = NSWorkspace.shared.frontmostApplication { handle(app) }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    func current() -> AppInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return info(for: app)
    }

    private func handle(_ app: NSRunningApplication) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.handle(app) }
            return
        }
        guard let info = info(for: app), info.key != lastKey else { return }
        lastKey = info.key
        onAppChange?(info)
    }

    private func info(for app: NSRunningApplication) -> AppInfo? {
        guard app.activationPolicy == .regular else { return nil }
        guard let bundleID = app.bundleIdentifier, !bundleID.isEmpty else { return nil }
        return AppInfo(
            bundleID: bundleID,
            name: Self.displayName(for: app),
            pid: app.processIdentifier,
            launchedAt: app.launchDate
        )
    }

    private static func displayName(for app: NSRunningApplication) -> String {
        if let name = app.localizedName, !name.isEmpty { return name }
        if let path = app.bundleURL?.path {
            let name = FileManager.default.displayName(atPath: path)
            if !name.isEmpty { return name }
        }
        return app.bundleIdentifier ?? "Unknown"
    }
}
