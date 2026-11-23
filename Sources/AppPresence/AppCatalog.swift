import AppKit

struct InstalledApp: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
}

enum AppCatalog {
    static func load() -> [InstalledApp] {
        let roots = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
        ]
        var seen = Set<String>()
        var apps: [InstalledApp] = []

        for root in roots {
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
            for entry in entries where entry.hasSuffix(".app") {
                let path = root + "/" + entry
                guard let bundle = Bundle(path: path), let id = bundle.bundleIdentifier else { continue }
                guard !seen.contains(id) else { continue }
                guard isUserFacing(bundle) else { continue }
                seen.insert(id)
                apps.append(InstalledApp(id: id, name: FileManager.default.displayName(atPath: path), path: path))
            }
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func isUserFacing(_ bundle: Bundle) -> Bool {
        let info = bundle.infoDictionary ?? [:]
        for key in ["LSUIElement", "LSBackgroundOnly"] where flag(info[key]) {
            return false
        }
        return true
    }

    private static func flag(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String { return text == "1" || text.lowercased() == "true" }
        return false
    }
}
