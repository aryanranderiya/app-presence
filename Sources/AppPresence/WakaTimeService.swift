import Foundation

struct WakaTimeSnapshot {
    let total: String
    let facts: [String]
    let hover: String
}

final class WakaTimeService {
    static let iconURL = "https://cdn.jsdelivr.net/gh/aryanranderiya/app-presence@main/icons/macos-wakatime.WakaTime.png"

    private let rpc: DiscordRPC
    private let store: Store
    private var refreshTimer: Timer?
    private var rotateTimer: Timer?
    private var snapshot: WakaTimeSnapshot?
    private var rotation = 0

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

        rotateTimer?.invalidate()
        rotateTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            self?.rotate()
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        rotateTimer?.invalidate()
        rotateTimer = nil
        rpc.clearActivity()
    }

    func shutdown() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        rotateTimer?.invalidate()
        rotateTimer = nil
        rpc.shutdown()
    }

    func refresh() {
        Self.fetch { [weak self] snapshot in
            guard let self, let snapshot else { return }
            self.snapshot = snapshot
            self.push()
        }
    }

    private func rotate() {
        guard snapshot != nil else { return }
        rotation += 1
        push()
    }

    private func push() {
        guard let snapshot else { return }
        let fact = snapshot.facts.isEmpty ? nil : snapshot.facts[rotation % snapshot.facts.count]
        rpc.setActivity(Presence(
            name: "WakaTime",
            details: snapshot.total,
            state: fact,
            iconURL: Self.iconURL,
            iconText: snapshot.hover,
            buttons: [
                PresenceButton(label: "Dashboard", url: "https://wakatime.com/dashboard"),
                PresenceButton(label: "Leaderboard", url: "https://wakatime.com/leaders"),
            ]
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

            var facts: [String] = []
            if let first = projects.first, let name = first["name"] as? String {
                facts.append(join(name, first["text"] as? String))
            }
            if let language = languages.first(where: { ($0["name"] as? String)?.lowercased() != "other" }),
               let name = language["name"] as? String {
                facts.append(join(name, language["text"] as? String))
            }
            if let first = editors.first, let name = first["name"] as? String {
                facts.append(join(name, first["text"] as? String))
            }
            if projects.count > 1 {
                facts.append("\(projects.count) projects today")
            }
            if aiLines > 0 {
                facts.append("\(aiLines) AI lines")
            }

            let hover = ["WakaTime", editors.first?["name"] as? String, systems.first?["name"] as? String]
                .compactMap { $0 }
                .joined(separator: " · ")

            let snapshot = WakaTimeSnapshot(
                total: "\(hours)h \(minutes)m today",
                facts: facts,
                hover: hover
            )
            log("wakatime \(snapshot.total) \(facts.first ?? "")")
            DispatchQueue.main.async { completion(snapshot) }
        }.resume()
    }

    private static func join(_ name: String, _ text: String?) -> String {
        guard let text, !text.isEmpty else { return name }
        return "\(name) · \(text)"
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
