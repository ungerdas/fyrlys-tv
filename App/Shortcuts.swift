#if !os(tvOS)
import AppIntents
import FyrlysCore
import Foundation
import UserNotifications

/// Siri og Snarveier (iPhone, iPad og Mac): «Spill NRK1 i Fyrlys». Kanalene Siri kjenner, er favorittene og de sist
/// sette (appen lagrer navnene på enheten når de endres); handlingen åpner appen og spiller kanalen.
struct ChannelEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Kanal"
    static var defaultQuery = ChannelQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ChannelQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ChannelEntity] {
        let wanted = Set(identifiers)
        return ShortcutChannels.load().filter { wanted.contains($0.id) }
    }

    /// «NRK1», «nrk 1» og «NRK1 HD» er samme kanal (`channelKey`); ellers en del av navnet.
    func entities(matching string: String) async throws -> [ChannelEntity] {
        let all = ShortcutChannels.load()
        let key = channelKey(string)
        let exact = all.filter { !key.isEmpty && channelKey($0.name) == key }
        if !exact.isEmpty { return exact }
        let text = string.lowercased()
        return all.filter { $0.name.lowercased().contains(text) }
    }

    func suggestedEntities() async throws -> [ChannelEntity] {
        ShortcutChannels.load()
    }
}

struct PlayChannelIntent: AppIntent {
    static var title: LocalizedStringResource = "Spill en kanal"
    static var description = IntentDescription("Åpner Fyrlys og spiller kanalen.")
    static var openAppWhenRun = true

    @Parameter(title: "Kanal")
    var channel: ChannelEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Spill \(\.$channel)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentInbox.play(channel.id)
        return .result()
    }
}

struct FyrlysShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayChannelIntent(),
                    phrases: ["Spill \(\.$channel) i \(.applicationName)",
                              "Se \(\.$channel) i \(.applicationName)",
                              "Sett på \(\.$channel) i \(.applicationName)",
                              "Play \(\.$channel) in \(.applicationName)",
                              "Watch \(\.$channel) in \(.applicationName)"],
                    shortTitle: "Spill en kanal",
                    systemImageName: "play.tv")
    }
}

/// Kanalen Siri ba om: HomeView spiller den når lista er klar (som Top Shelf og varslene).
@MainActor
enum IntentInbox {
    private(set) static var pending: String?

    static func play(_ id: String) {
        pending = id
        NotificationCenter.default.post(name: .fyrlysIntentPlay, object: nil)
    }

    static func take() -> String? {
        defer { pending = nil }
        return pending
    }
}

extension Notification.Name {
    static let fyrlysIntentPlay = Notification.Name("fyrlysIntentPlay")
}

/// Favorittene og de sist sette (id og navn) for Siri, på enheten.
enum ShortcutChannels {
    static let key = "snarvei-kanaler"

    static func save(_ channels: [Channel]) {
        var seen = Set<String>()
        let list = channels.compactMap { channel -> [String: String]? in
            guard seen.insert(channel.id).inserted else { return nil }
            return ["id": channel.id, "name": nameParts(channel.name).main]
        }
        UserDefaults.standard.set(list, forKey: key)
        FyrlysShortcuts.updateAppShortcutParameters()
    }

    static func load() -> [ChannelEntity] {
        let list = UserDefaults.standard.array(forKey: key) as? [[String: String]] ?? []
        return list.compactMap { row in
            guard let id = row["id"], let name = row["name"] else { return nil }
            return ChannelEntity(id: id, name: name)
        }
    }
}

/// «Minn meg på» i guiden (iPhone, iPad og Mac): et varsel to minutter før programmet begynner; trykk på det spiller
/// kanalen.
@MainActor
enum Reminders {
    static let lead: TimeInterval = 120

    static func id(_ channel: Channel, _ program: Program) -> String {
        "paminnelse-\(channel.id)-\(Int(program.start.timeIntervalSince1970))"
    }

    static func isSet(_ channel: Channel, _ program: Program) async -> Bool {
        let wanted = id(channel, program)
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return pending.contains { $0.identifier == wanted }
    }

    /// Setter eller fjerner påminnelsen; svarer om den er satt etterpå (nei også når varsler ikke er tillatt).
    static func toggle(_ channel: Channel, _ program: Program) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let key = id(channel, program)
        if await isSet(channel, program) {
            center.removePendingNotificationRequests(withIdentifiers: [key])
            return false
        }
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }
        let content = UNMutableNotificationContent()
        content.title = program.title
        content.body = L("Begynner {time} på {channel}", ["time": hhmm(program.start),
                                                          "channel": nameParts(channel.name).main])
        content.sound = .default
        content.userInfo = ["kanal": channel.id]
        let wait = max(1, program.start.timeIntervalSinceNow - lead)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: key, content: content, trigger: trigger))
            AppLog.shared.add("Påminnelse satt for kanal \(channel.id)")
            return true
        } catch {
            return false
        }
    }
}

/// Varslene: vises også når appen er framme, og et trykk spiller kanalen.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["kanal"] as? String
        Task { @MainActor in
            if let id { IntentInbox.play(id) }
            done()
        }
    }
}
#endif
