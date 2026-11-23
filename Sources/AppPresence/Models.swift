import Foundation

struct AppInfo: Equatable {
    let bundleID: String
    let name: String

    var iconURL: String {
        let base = "https://cdn.jsdelivr.net/gh/aryanranderiya/app-presence@main/icons/"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = bundleID.addingPercentEncoding(withAllowedCharacters: allowed) ?? bundleID
        return base + encoded + ".png"
    }
}

final class AppRegistry {
    private let ownBundleID = Bundle.main.bundleIdentifier
    private let overrides = [
        "com.google.chrome": "Chrome", "com.apple.safari": "Safari", "com.microsoft.vscode": "VS Code",
        "com.apple.terminal": "Terminal", "com.mitchellh.ghostty": "Ghostty",
    ]
    private let privateBundleIDs: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.apple.keychainaccess", "com.apple.mobilesms", "com.apple.ichat",
        "org.whispersystems.signal-desktop", "net.whatsapp.whatsapp", "com.whatsapp.whatsapp",
        "com.apple.passwords",
    ]

    func resolve(_ app: AppInfo) -> AppInfo? {
        if app.bundleID == ownBundleID { return nil }
        let key = app.bundleID.lowercased()
        if privateBundleIDs.contains(key) || key.contains("bank") { return nil }
        guard let name = overrides[key] else { return app }
        return AppInfo(bundleID: app.bundleID, name: name)
    }
}
