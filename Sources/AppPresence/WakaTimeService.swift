import Foundation

struct WakaTimeSnapshot {
    let total: String
    let summary: String
    let hover: String
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
        rpc.setActivity(Presence(
            name: "WakaTime",
            details: snapshot.total,
            state: snapshot.summary.isEmpty ? nil : snapshot.summary,
            iconURL: Self.iconURL,
            iconText: snapshot.hover,
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
        let credentials = Data((key + ":").utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")

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
            let languages = payload["languages"] as? [[String: Any]] ?? []
            let editors = payload["editors"] as? [[String: Any]] ?? []
            let systems = payload["operating_systems"] as? [[String: Any]] ?? []

            let project = projects.first?["name"] as? String
            let languageItem = languages.first { ($0["name"] as? String)?.lowercased() != "other" }
            let language = languageItem?["name"] as? String
            let editor = editors.first?["name"] as? String
            let system = systems.first?["name"] as? String

            let projectPart = project.map { "\($0) \(compact(projects.first?["total_seconds"] as? Double ?? 0))" }
            let languagePart = language.map { "\($0) \(compact(languageItem?["total_seconds"] as? Double ?? 0))" }
            let summary = [projectPart, languagePart].compactMap { $0 }.joined(separator: " · ")

            var hoverParts: [String] = []
            if let editor { hoverParts.append("\(editor) \(compact(editors.first?["total_seconds"] as? Double ?? 0))") }
            hoverParts.append("\(projects.count) projects")
            if let system { hoverParts.append(system) }
            if aiLines > 0 { hoverParts.append("\(aiLines) AI lines") }

            let snapshot = WakaTimeSnapshot(
                total: "\(hours)h \(minutes)m today",
                summary: summary,
                hover: hoverParts.joined(separator: " · ")
            )
            log("wakatime \(snapshot.total) \(summary)")
            DispatchQueue.main.async { completion(snapshot) }
        }.resume()
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
