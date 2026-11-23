import AppKit
import Combine
import SwiftUI

final class SettingsModel: ObservableObject {
    let store = Store.shared
    var onChange: () -> Void = {}

    @Published var apps: [InstalledApp] = []
    @Published var query = ""
    @Published var policies: [String: AppPolicy] = [:]
    @Published var phrases: [String: String] = [:]
    @Published var details: [String: String] = [:]
    @Published var blocked: [BlockedApp] = []
    @Published var tab = 0
    @Published var cardName = "Now Playing"
    @Published var wakaEnabled = false
    @Published var wakaClientID = ""
    @Published var wakaStatus = "Checking…"
    @Published var showBlocked = false

    var filteredApps: [InstalledApp] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return apps.filter { app in
            guard policies[app.id] != .never else { return false }
            guard !needle.isEmpty else { return true }
            return app.name.lowercased().contains(needle) || app.id.lowercased().contains(needle)
        }
    }

    func load() {
        apps = AppCatalog.load()
        var map: [String: AppPolicy] = [:]
        for app in apps { map[app.id] = store.policy(for: app.id) }
        policies = map
        phrases = store.allPhrases()
        details = store.allDetails()
        blocked = store.blockedApps()
        cardName = store.setting("card_name") ?? "Now Playing"
        wakaEnabled = store.setting("wakatime_enabled") == "1"
        wakaClientID = store.setting("wakatime_client_id") ?? ""
        refreshWaka()
    }

    func setPolicy(_ app: InstalledApp, _ policy: AppPolicy) {
        policies[app.id] = policy
        store.setPolicy(policy, bundleID: app.id, name: app.name)
        blocked = store.blockedApps()
        onChange()
    }

    func unblock(_ item: BlockedApp) {
        policies[item.id] = .off
        store.setPolicy(.off, bundleID: item.id, name: item.name)
        blocked = store.blockedApps()
        onChange()
    }

    func setPhrase(_ app: InstalledApp, _ text: String) {
        phrases[app.id] = text
        store.setPhrase(text, for: app.id)
        onChange()
    }

    func setDetail(_ app: InstalledApp, _ text: String) {
        details[app.id] = text
        store.setDetail(text, for: app.id)
        onChange()
    }

    func setCardName(_ value: String) {
        store.setSetting("card_name", value)
        onChange()
    }

    func setWakaEnabled(_ value: Bool) {
        store.setSetting("wakatime_enabled", value ? "1" : "0")
        onChange()
    }

    func setWakaClientID(_ value: String) {
        store.setSetting("wakatime_client_id", value)
        onChange()
    }

    func refreshWaka() {
        wakaStatus = "Checking…"
        WakaTimeService.fetch { [weak self] snapshot in
            guard let self else { return }
            guard let snapshot else {
                self.wakaStatus = "Could not reach WakaTime"
                return
            }
            let extra = snapshot.summary
            self.wakaStatus = extra.isEmpty ? snapshot.total : "\(snapshot.total) · \(extra)"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 14) {
            header
            Picker("", selection: $model.tab) {
                Text("Apps").tag(0)
                Text("WakaTime").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)

            if model.tab == 0 { appsTab } else { wakaTab }
        }
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(width: 620, height: 680)
        .onAppear(perform: model.load)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("AppPresence")
                    .font(.system(size: 17, weight: .semibold))
                Text("Choose what appears on your Discord profile.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var appsTab: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search apps", text: $model.query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .textBackgroundColor)))

            List(model.filteredApps) { app in
                row(app)
            }
            .listStyle(.inset)

            blockedSection

            HStack(spacing: 8) {
                Text("Card title")
                    .font(.system(size: 12))
                TextField("Now Playing", text: $model.cardName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
                    .onChange(of: model.cardName) { value in
                        model.setCardName(value)
                    }
                Spacer()
                Text("Turn on an app, then give it a line.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
    }

    private func row(_ app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { model.policies[app.id] == .show },
                set: { isOn in model.setPolicy(app, isOn ? .show : .off) }
            )) {
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                        .resizable()
                        .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name)
                            .font(.system(size: 13))
                        Text(app.id)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if model.policies[app.id] == .show {
                TextField("Add a status line", text: Binding(
                    get: { model.phrases[app.id] ?? "" },
                    set: { value in model.setPhrase(app, value) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .padding(.leading, 32)

                TextField("Add a detail line", text: Binding(
                    get: { model.details[app.id] ?? "" },
                    set: { value in model.setDetail(app, value) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .padding(.leading, 32)
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Always hide") { model.setPolicy(app, .never) }
            Button("Hide") { model.setPolicy(app, .off) }
        }
    }

    private var blockedSection: some View {
        DisclosureGroup(isExpanded: $model.showBlocked) {
            if model.blocked.isEmpty {
                Text("Nothing blocked.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(model.blocked) { item in
                    HStack {
                        Text(item.name)
                            .font(.system(size: 12))
                        Spacer()
                        Button {
                            model.unblock(item)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Always hidden")
                    .font(.system(size: 12, weight: .medium))
                Text("\(model.blocked.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Menu {
                    ForEach(model.apps.filter { model.policies[$0.id] != .never }) { app in
                        Button(app.name) { model.setPolicy(app, .never) }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
            }
        }
    }

    private var wakaTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Show a WakaTime card", isOn: Binding(
                get: { model.wakaEnabled },
                set: { value in
                    model.wakaEnabled = value
                    model.setWakaEnabled(value)
                }
            ))

            HStack(spacing: 8) {
                Text("Application ID")
                    .font(.system(size: 12))
                TextField("Second Discord application", text: Binding(
                    get: { model.wakaClientID },
                    set: { value in
                        model.wakaClientID = value
                        model.setWakaClientID(value)
                    }
                ))
                .textFieldStyle(.roundedBorder)
            }

            Text("Discord shows one card per application. Create a second application, then paste its Application ID here.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Developer Portal") {
                if let url = URL(string: "https://discord.com/developers/applications") {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            HStack {
                Text("Today")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button("Refresh") { model.refreshWaka() }
            }

            Text(model.wakaStatus)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 20)
    }
}
