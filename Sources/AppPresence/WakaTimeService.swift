import Foundation

struct WakaTimeSnapshot {
    let total: String
    let summary: String
    let hover: String
    let rank: Int?
}

final class WakaTimeService {
    static let iconURL = "https://cdn.jsdelivr.net/gh/aryanranderiya/app-presence@main/icons/macos-wakatime.WakaTime.png"

    private let rpc: DiscordRPC
    private let store: Store
    private var refreshTimer: Timer?
    private var snapshot: WakaTimeSnapshot?

    init(rpc: DiscordRPC, store: Store) {
        self.rpc = rpc
        self.store = store
    }

    var isConfigured: Bool {
        store.setting("wakatime_enabled") == "1" && !(store.setting("wakatime_client_id") ?? "").isEmpty
    }

    func start() {
        guard isConfigured else { return }
        rpc.connect()
        refresh()

        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        rpc.clearActivity()
    }

    func shutdown() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        rpc.shutdown()
    }

    func refresh() {
        Self.fetch { [weak self] snapshot in
            guard let self, let snapshot else { return }
            self.snapshot = snapshot
            self.push()
        }
    }

    private func push() {
        guard let snapshot else { return }
        let details = snapshot.rank.map { "\(snapshot.total) • Rank #\($0)" } ?? snapshot.total
        let hover = snapshot.rank.map { "Rank #\($0) this week · \(snapshot.hover)" } ?? snapshot.hover
        rpc.setActivity(Presence(
            name: "WakaTime",
            details: details,
            state: snapshot.summary.isEmpty ? nil : snapshot.summary,
            iconURL: Self.iconURL,
            iconText: hover,
            buttons: [
                PresenceButton(label: "Dashboard", url: "https://wakatime.com/dashboard"),
                PresenceButton(label: "Leaderboard", url: "https://wakatime.com/leaders"),
            ],
            type: 3
        ))
    }

    static func fetch(completion: @escaping (WakaTimeSnapshot?) -> Void) {
        guard let key = apiKey(), !key.isEmpty else {
            log("wakatime api key missing")
            DispatchQueue.main.async { completion(nil) }
            return
        }
        guard let url = URL(string: "https://wakatime.com/api/v1/users/current/status_bar/today") else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Basic \(Data((key + ":").utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data, error == nil,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = root["data"] as? [String: Any] else {
                log("wakatime fetch failed")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let total = payload["grand_total"] as? [String: Any] ?? [:]
            let hours = total["hours"] as? Int ?? 0
            let minutes = total["minutes"] as? Int ?? 0
            let aiLines = total["ai_additions"] as? Int ?? 0

            let projects = payload["projects"] as? [[String: Any]] ?? []
            let editors = payload["editors"] as? [[String: Any]] ?? []
            let systems = payload["operating_systems"] as? [[String: Any]] ?? []

            var hoverParts: [String] = []
            if let editor = editors.first?["name"] as? String {
                hoverParts.append("\(editor) \(compact(editors.first?["total_seconds"] as? Double ?? 0))")
            }
            hoverParts.append("\(projects.count) projects")
            if let system = systems.first?["name"] as? String { hoverParts.append(system) }
            if aiLines > 0 { hoverParts.append("\(aiLines) AI lines") }

            fetchLeaderboard(key: key) { board in
                var summaryParts: [String] = []
                if let board {
                    if board.dailySeconds > 0 { summaryParts.append("\(hoursOnly(board.dailySeconds))/day") }
                    if board.weekSeconds > 0 { summaryParts.append("\(hoursOnly(board.weekSeconds))/week") }
                }

                let snapshot = WakaTimeSnapshot(
                    total: "\(hours)h \(minutes)m today",
                    summary: summaryParts.joined(separator: " • "),
                    hover: hoverParts.joined(separator: " · "),
                    rank: board?.rank
                )
                log("wakatime \(snapshot.total) rank=\(board.map { String($0.rank) } ?? "-") \(snapshot.summary)")
                DispatchQueue.main.async { completion(snapshot) }
            }
        }.resume()
    }

    private struct Leaderboard {
        let rank: Int
        let weekSeconds: Double
        let dailySeconds: Double
    }

    private static func fetchLeaderboard(key: String, completion: @escaping (Leaderboard?) -> Void) {
        fetchPage(key, page: 1) { first in
            guard let first,
                  let current = first["current_user"] as? [String: Any],
                  let rank = current["rank"] as? Int else {
                completion(nil)
                return
            }
            let page = current["page"] as? Int ?? 1

            fetchPage(key, page: page) { target in
                guard let target,
                      let entries = target["data"] as? [[String: Any]],
                      let entry = entries.first(where: { ($0["rank"] as? Int) == rank }),
                      let running = entry["running_total"] as? [String: Any] else {
                    completion(Leaderboard(rank: rank, weekSeconds: 0, dailySeconds: 0))
                    return
                }
                completion(Leaderboard(
                    rank: rank,
                    weekSeconds: running["total_seconds"] as? Double ?? 0,
                    dailySeconds: running["daily_average"] as? Double ?? 0
                ))
            }
        }
    }

    private static func fetchPage(_ key: String, page: Int, completion: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: "https://wakatime.com/api/v1/leaders?page=\(page)") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Basic \(Data((key + ":").utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil)
                return
            }
            completion(root)
        }.resume()
    }

    private static func hoursOnly(_ seconds: Double) -> String {
        let hours = Int((max(seconds, 0) / 3600).rounded())
        return "\(hours)h"
    }

    private static func compact(_ seconds: Double) -> String {
        let total = max(Int(seconds), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private static func apiKey() -> String? {
        let path = NSHomeDirectory() + "/.wakatime.cfg"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("api_key") {
            guard let value = line.split(separator: "=", maxSplits: 1).last else { continue }
            return value.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}
