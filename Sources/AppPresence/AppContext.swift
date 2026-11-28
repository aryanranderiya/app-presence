import Foundation
import SQLite3

enum AppContext {
    static var onChange: ((String) -> Void)?

    private struct Entry {
        var detail: String?
        var fetchedAt: Date
    }

    private static let queue = DispatchQueue(label: "apppresence.context", qos: .utility)
    private static let lock = NSLock()
    private static var cache: [String: Entry] = [:]
    private static var inFlight: Set<String> = []
    private static let maxAge: TimeInterval = 4

    static func detail(for bundleID: String) -> String? {
        switch bundleID {
        case "com.conductor.app", "com.superlogical.rex":
            break
        default:
            return nil
        }

        lock.lock()
        let entry = cache[bundleID]
        let stale = entry.map { Date().timeIntervalSince($0.fetchedAt) >= maxAge } ?? true
        let refresh = stale && !inFlight.contains(bundleID)
        if refresh { inFlight.insert(bundleID) }
        lock.unlock()

        if refresh {
            queue.async { load(bundleID) }
        }
        return entry?.detail
    }

    private static func load(_ bundleID: String) {
        let detail = bundleID == "com.conductor.app" ? conductorDetail() : rexDetail()

        lock.lock()
        let previous = cache[bundleID]?.detail
        cache[bundleID] = Entry(detail: detail, fetchedAt: Date())
        inFlight.remove(bundleID)
        lock.unlock()

        guard previous != detail else { return }
        DispatchQueue.main.async { onChange?(bundleID) }
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
        SELECT s.title, COALESCE(r.name, w.directory_name), w.branch
        FROM workspaces w
        LEFT JOIN sessions s ON s.id = w.active_session_id
        LEFT JOIN repos r ON r.id = w.\(repoColumn)
        WHERE COALESCE(w.state, '') != 'archived'
          AND s.title IS NOT NULL AND TRIM(s.title) != ''
        ORDER BY COALESCE(w.last_activity_at, w.updated_at) DESC
        LIMIT 1;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        let title = columnText(statement, 0)
        let repo = columnText(statement, 1)
        let branch = columnText(statement, 2)

        if let title {
            return title
        }
        if let repo, let branch, !branch.isEmpty {
            return "\(repo) · \(branch)"
        }
        return repo
    }

    private static func rexDetail() -> String? {
        guard let rex = rexBinary() else { return nil }
        guard let listText = run(rex, ["ls", "--json"]),
              let list = try? JSONSerialization.jsonObject(with: Data(listText.utf8)) as? [String: Any],
              let sessions = list["sessions"] as? [[String: Any]],
              let sessionID = sessions.first?["session_id"] as? String,
              let inspectText = run(rex, ["session", "inspect", sessionID, "--json"]),
              let inspect = try? JSONSerialization.jsonObject(with: Data(inspectText.utf8)) as? [String: Any],
              let active = inspect["active_window_id"] as? String,
              let windows = inspect["windows"] as? [[String: Any]],
              let window = windows.first(where: { ($0["window_id"] as? String) == active })
        else { return nil }

        if let block = window["focused_block_id"] as? String,
           let titleText = run(rex, ["block", "call", "title", "-b", block]),
           let titleData = titleText.data(using: .utf8),
           let titleObject = try? JSONSerialization.jsonObject(with: titleData) as? [String: Any],
           let title = titleObject["title"] as? String,
           !title.isEmpty {
            return title
        }

        if let label = window["label"] as? String, !label.isEmpty, !label.hasPrefix("Window ") {
            return label
        }
        return inspect["label"] as? String
    }

    private static func rexBinary() -> String? {
        let candidates = [
            NSHomeDirectory() + "/.local/bin/rex",
            "/opt/homebrew/bin/rex",
            "/usr/local/bin/rex",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func run(_ binary: String, _ arguments: [String], timeout: TimeInterval = 2) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
        } catch {
            return nil
        }

        var output = Data()
        let read = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            output = pipe.fileHandleForReading.readDataToEndOfFile()
            read.signal()
        }

        let deadline = Date().addingTimeInterval(timeout)
        guard read.wait(timeout: .now() + timeout) == .success else {
            stop(process)
            return nil
        }
        while process.isRunning, Date() < deadline {
            usleep(20_000)
        }
        guard !process.isRunning else {
            stop(process)
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: output, encoding: .utf8)
    }

    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(0.5)
        while process.isRunning, Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
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
