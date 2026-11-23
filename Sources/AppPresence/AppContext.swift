import Foundation
import SQLite3

enum AppContext {
    private static let lock = NSLock()
    private static var cachedAt = Date.distantPast
    private static var cachedBundleID = ""
    private static var cachedDetail: String?

    static func detail(for bundleID: String) -> String? {
        guard bundleID == "com.conductor.app" else { return nil }

        lock.lock()
        defer { lock.unlock() }

        if cachedBundleID == bundleID, Date().timeIntervalSince(cachedAt) < 5 {
            return cachedDetail
        }

        let detail = conductorDetail()
        cachedAt = Date()
        cachedBundleID = bundleID
        cachedDetail = detail
        return detail
    }

    private static func conductorDetail() -> String? {
        let path = NSHomeDirectory() + "/Library/Application Support/com.conductor.app/conductor.db"
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return nil
        }
        defer { sqlite3_close(db) }

        let repoColumn = hasColumn(db, table: "workspaces", column: "project_id") ? "project_id" : "repository_id"
        let sql = """
        SELECT COALESCE(r.name, w.directory_name), w.branch
        FROM sessions s
        LEFT JOIN workspaces w ON w.id = s.workspace_id
        LEFT JOIN repos r ON r.id = w.\(repoColumn)
        WHERE s.status IN ('working', 'waiting')
        ORDER BY s.last_message_at DESC
        LIMIT 1;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        let repo = columnText(statement, 0)
        let branch = columnText(statement, 1)

        if let repo, let branch, !branch.isEmpty {
            return "\(repo) · \(branch)"
        }
        return repo
    }

    private static func hasColumn(_ db: OpaquePointer, table: String, column: String) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = columnText(statement, 1), name == column { return true }
        }
        return false
    }

    private static func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let raw = sqlite3_column_text(statement, index) else { return nil }
        let value = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
