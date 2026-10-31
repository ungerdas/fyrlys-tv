import Foundation

/// Kategoriene og kanalene fra sist, på disk, så appen er klar med en gang den starter (lista hentes på nytt i
/// bakgrunnen).
public struct Lists: Codable, Sendable {
    public let categories: [ChannelCategory]
    public let channels: [Channel]
    public let saved: Date

    public init(categories: [ChannelCategory], channels: [Channel], saved: Date = Date()) {
        self.categories = categories
        self.channels = channels
        self.saved = saved
    }
}

public struct ListCache: Sendable {
    let dir: URL

    public init(dir: URL) { self.dir = dir }

    /// I Caches på enheten (tvOS kan rydde der når det trengs plass; da hentes lista bare på nytt).
    public static var standard: ListCache {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return ListCache(dir: base.appendingPathComponent("lister", isDirectory: true))
    }

    func file(_ loginId: String) -> URL { dir.appendingPathComponent("\(loginId).json") }

    public func read(_ loginId: String) -> Lists? {
        guard let data = try? Data(contentsOf: file(loginId)) else { return nil }
        return try? JSONDecoder().decode(Lists.self, from: data)
    }

    public func write(_ lists: Lists, for loginId: String) {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try JSONEncoder().encode(lists).write(to: file(loginId), options: .atomic)
        } catch {
            // neste gang hentes lista bare på nytt
        }
    }

    public func remove(_ loginId: String) {
        try? FileManager.default.removeItem(at: file(loginId))
    }
}
