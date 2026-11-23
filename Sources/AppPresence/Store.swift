import Foundation
import SQLite3

struct BlockedApp: Identifiable {
    let id: String
    let name: String
}

final class Store {
    static let shared = Store()

    private var db: OpaquePointer?
    private let lock = NSLock()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppPresence", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let path = base.appendingPathComponent("apppresence.sqlite3").path

        guard sqlite3_open(path, &db) == SQLITE_OK else {
            log("sqlite open failed")
            db = nil
            return
        }
        migrate()
        seed()
        log("store ready \(path)")
    }

    private func migrate() {
        exec("PRAGMA journal_mode=WAL;")
        exec("""
        CREATE TABLE IF NOT EXISTS apps (
            bundle_id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            policy TEXT NOT NULL,
            updated_at INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS phrases (
            bundle_id TEXT PRIMARY KEY,
            text TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """)
    }

    private func seed() {
        lock.lock()
        defer { lock.unlock() }

        if settingLocked("seeded") != "1" {
            let alwaysHidden = [
                ("com.1password.1password", "1Password"),
                ("com.agilebits.onepassword7", "1Password 7"),
                ("com.bitwarden.desktop", "Bitwarden"),
                ("com.apple.keychainaccess", "Keychain Access"),
                ("com.apple.mobilesms", "Messages"),
                ("com.apple.ichat", "Messages"),
                ("com.apple.passwords", "Passwords"),
                ("org.whispersystems.signal-desktop", "Signal"),
                ("net.whatsapp.whatsapp", "WhatsApp"),
                ("com.whatsapp.whatsapp", "WhatsApp"),
                ("com.hnc.Discord", "Discord"),
            ]
            for (id, name) in alwaysHidden {
                setPolicyLocked(.never, bundleID: id, name: name)
            }
            setSettingLocked("card_name", "Now Playing")
            setSettingLocked("sticky", "1")
            setSettingLocked("wakatime_enabled", "0")
            setSettingLocked("wakatime_client_id", "")
            setSettingLocked("seeded", "1")

            let legacy = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
            setSettingLocked("enabled", legacy ? "1" : "0")
        }

        if settingLocked("phrases_seeded") != "1" {
            for (id, text) in Self.defaultPhrases {
                setPhraseLocked(text, bundleID: id)
            }
            setSettingLocked("phrases_seeded", "1")
        }
    }

    func policy(for bundleID: String) -> AppPolicy {
        if bundleID.lowercased().contains("bank") { return .never }
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return .off }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT policy FROM apps WHERE bundle_id = ?", -1, &statement, nil) == SQLITE_OK else { return .off }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, bundleID, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW, let raw = sqlite3_column_text(statement, 0) else { return .off }
        return AppPolicy(rawValue: String(cString: raw)) ?? .off
    }

    func setPolicy(_ policy: AppPolicy, bundleID: String, name: String) {
        lock.lock()
        defer { lock.unlock() }
        setPolicyLocked(policy, bundleID: bundleID, name: name)
    }

    func blockedApps() -> [BlockedApp] {        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT bundle_id, name FROM apps WHERE policy = 'never' ORDER BY name COLLATE NOCASE", -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var out: [BlockedApp] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            out.append(BlockedApp(
                id: String(cString: sqlite3_column_text(statement, 0)),
                name: String(cString: sqlite3_column_text(statement, 1))
            ))
        }
        return out
    }

    func allowedCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return 0 }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM apps WHERE policy = 'show'", -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    func phrase(for bundleID: String) -> String? {        lock.lock()
        defer { lock.unlock() }
        return phraseLocked(bundleID)
    }

    func setPhrase(_ text: String, for bundleID: String) {
        lock.lock()
        defer { lock.unlock() }
        setPhraseLocked(text, bundleID: bundleID)
    }

    func allPhrases() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [:] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT bundle_id, text FROM phrases", -1, &statement, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(statement) }
        var out: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            out[String(cString: sqlite3_column_text(statement, 0))] = String(cString: sqlite3_column_text(statement, 1))
        }
        return out
    }

    func setting(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return settingLocked(key)
    }

    func setSetting(_ key: String, _ value: String) {
        lock.lock()
        defer { lock.unlock() }
        setSettingLocked(key, value)
    }

    private func setPolicyLocked(_ policy: AppPolicy, bundleID: String, name: String) {
        guard let db else { return }
        var statement: OpaquePointer?
        let sql = """
        INSERT INTO apps (bundle_id, name, policy, updated_at) VALUES (?, ?, ?, ?)
        ON CONFLICT(bundle_id) DO UPDATE SET policy = excluded.policy, name = excluded.name, updated_at = excluded.updated_at
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, bundleID, -1, transient)
        sqlite3_bind_text(statement, 2, name, -1, transient)
        sqlite3_bind_text(statement, 3, policy.rawValue, -1, transient)
        sqlite3_bind_int64(statement, 4, Int64(Date().timeIntervalSince1970))
        sqlite3_step(statement)
    }

    private func phraseLocked(_ bundleID: String) -> String? {
        guard let db else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT text FROM phrases WHERE bundle_id = ?", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, bundleID, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW, let raw = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: raw)
    }

    private func setPhraseLocked(_ text: String, bundleID: String) {
        guard let db else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM phrases WHERE bundle_id = ?", -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, bundleID, -1, transient)
            sqlite3_step(statement)
            return
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO phrases (bundle_id, text) VALUES (?, ?) ON CONFLICT(bundle_id) DO UPDATE SET text = excluded.text", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, bundleID, -1, transient)
        sqlite3_bind_text(statement, 2, trimmed, -1, transient)
        sqlite3_step(statement)
    }

    private func settingLocked(_ key: String) -> String? {
        guard let db else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM settings WHERE key = ?", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW, let raw = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: raw)
    }

    private func setSettingLocked(_ key: String, _ value: String) {
        guard let db else { return }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, transient)
        sqlite3_bind_text(statement, 2, value, -1, transient)
        sqlite3_step(statement)
    }

    private func exec(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private static let defaultPhrases: [String: String] = [
        "com.superlogical.rex": "shipping with rex",
        "com.conductor.app": "conducting agents",
        "company.thebrowser.Browser": "browsing",
        "company.thebrowser.dia": "browsing",
        "com.mitchellh.ghostty": "in the terminal",
        "com.apple.Terminal": "in the terminal",
        "com.cmuxterm.app": "multiplexing",
        "com.linear": "triaging issues",
        "notion.id": "writing docs",
        "com.tinyspeck.slackmacgap": "in slack",
        "com.spotify.client": "listening",
        "com.google.Chrome": "browsing",
        "com.apple.Safari": "browsing",
        "com.microsoft.VSCode": "writing code",
        "com.openai.codex": "in codex",
        "com.electron.ollama": "running local models",
        "com.raycast.macos": "launching things",
        "com.hnc.Discord": "on discord",
        "com.apple.finder": "looking for files",
        "com.apple.mail": "reading email",
        "com.apple.iCal": "checking the calendar",
        "com.apple.Notes": "taking notes",
        "com.apple.Preview": "reading a pdf",
        "com.apple.QuickTimePlayerX": "watching something",
        "com.apple.Music": "listening",
        "com.apple.Photos": "in photos",
        "com.apple.Maps": "on the map",
        "com.apple.reminders": "checking reminders",
        "com.apple.systempreferences": "tweaking settings",
        "com.apple.ActivityMonitor": "watching processes",
        "com.apple.calculator": "doing math",
        "com.apple.TextEdit": "writing",
        "com.apple.iWork.Pages": "writing a doc",
        "com.apple.iWork.Numbers": "in a spreadsheet",
        "com.apple.iWork.Keynote": "building slides",
        "com.apple.iMovieApp": "editing video",
        "com.apple.GarageBand": "making music",
        "com.apple.iBooksX": "reading",
        "com.apple.AppStore": "browsing apps",
        "com.granola.app": "in a meeting",
        "anomaly.hex": "querying data",
        "com.if.Amphetamine": "keeping awake",
        "com.jordanbaird.Ice": "arranging the menu bar",
        "com.knollsoft.Rectangle": "snapping windows",
        "com.lowtechguys.Clop": "compressing",
        "me.damir.dropover-mac": "moving files",
        "net.whatsapp.WhatsApp": "on whatsapp",
        "ru.keepcoder.Telegram": "on telegram",
        "org.videolan.vlc": "watching something",
        "org.m0k.transmission": "downloading",
        "com.utmapp.UTM": "in a vm",
        "macos-wakatime.WakaTime": "checking stats",
        "app.swiftcord": "on swiftcord",
        "com.setapp.DesktopClient": "browsing setapp",
        "com.pilotmoon.scroll-reverser": "flipping scroll",
        "io.tailscale.ipn.macsys": "on the tailnet",
        "com.anthropic.claude-code-url-handler": "in claude code",
    ]
}
