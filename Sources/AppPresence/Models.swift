import Foundation

enum AppPolicy: String {
    case show
    case off
    case never
}

struct AppInfo: Equatable {
    let bundleID: String
    let name: String
    let pid: pid_t
    let launchedAt: Date?

    var key: String { "\(bundleID)#\(pid)" }

    var elapsed: String {
        guard let launchedAt else { return "" }
        return Self.duration(Date().timeIntervalSince(launchedAt))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }

    var iconURL: String {
        "https://cdn.jsdelivr.net/gh/aryanranderiya/app-presence@main/icons/\(bundleID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bundleID).png"
    }
}

struct PresenceButton {
    let label: String
    let url: String
}

struct Presence {
    let name: String
    let details: String
    var state: String? = nil
    let iconURL: String
    let iconText: String
    var startedAt: Date? = nil
    var buttons: [PresenceButton] = []
    var type: Int = 0

    var signature: String {
        let buttonKey = buttons.map { "\($0.label)|\($0.url)" }.joined(separator: ",")
        return "\(name)|\(details)|\(state ?? "")|\(iconURL)|\(startedAt?.timeIntervalSince1970 ?? 0)|\(buttonKey)|\(type)"
    }
}

final class AppRegistry {
    private let ownBundleID = Bundle.main.bundleIdentifier
    private let store = Store.shared
    private let overrides = [
        "com.google.chrome": "Chrome", "com.apple.safari": "Safari", "com.microsoft.vscode": "VS Code",
        "com.apple.terminal": "Terminal", "com.mitchellh.ghostty": "Ghostty",
    ]

    func resolve(_ app: AppInfo) -> AppInfo? {
        if app.bundleID == ownBundleID { return nil }
        guard store.policy(for: app.bundleID) == .show else { return nil }
        guard let name = overrides[app.bundleID.lowercased()] else { return app }
        return AppInfo(bundleID: app.bundleID, name: name, pid: app.pid, launchedAt: app.launchedAt)
    }

    func presence(for app: AppInfo) -> Presence {
        let phrase = store.phrase(for: app.bundleID)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (phrase?.isEmpty == false ? phrase : nil) ?? store.setting("card_name") ?? "Now Playing"
        let detail = AppContext.detail(for: app.bundleID) ?? store.detail(for: app.bundleID)
        return Presence(
            name: title,
            details: app.name,
            state: (detail?.isEmpty == false ? detail : nil),
            iconURL: app.iconURL,
            iconText: app.name,
            startedAt: app.launchedAt
        )
    }
}
