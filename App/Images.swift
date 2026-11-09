import FyrlysCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Bildene fra nettet: hentes én gang (User-Agent som VLC, som leverandørene liker), krympes til det de trengs i
/// (piksler, etter skjermen: Apple TV 4K og iPhone tegner med 2–3 piksler per punkt) og tas vare på i minnet sammen
/// med fargen bak dem (kanallogoene). Et bilde som er krympet mer enn et nytt sted trenger, hentes på nytt (fra
/// mellomlageret på disk) i den større størrelsen. En adresse som svarte med en feil eller ikke var et bilde, prøves
/// ikke igjen før etter ti minutter; var nettet borte eller tok det for lang tid, prøves den igjen etter et halvt minutt.
final class Images: @unchecked Sendable {
    static let shared = Images()

    /// piksler per punkt på denne skjermen (Apple TV HD 1, Apple TV 4K 2, iPhone 2–3)
    #if os(macOS)
    static let scale: CGFloat = max(1, NSScreen.main?.backingScaleFactor ?? 2)
    #else
    static let scale: CGFloat = max(1, UIScreen.main.scale)
    #endif
    /// det største et bilde holdes i (bakgrunnsbildene på Apple TV 4K ville ellers blitt 3840 piksler brede)
    static let maxPixels: CGFloat = 2048

    /// Piksler for et bilde som vises høyst [points] punkter bredt eller høyt.
    static func pixels(for points: CGFloat) -> CGFloat { min(maxPixels, (points * scale).rounded(.up)) }

    /// bildet og bakgrunnsfargen bak det (de store kortene), regnet ut én gang; sammen, så fargen ikke blir borte
    /// fra et bilde som fortsatt er i minnet
    private final class Entry {
        let image: UIImage
        let tint: Color?
        /// bildet er krympet til høyst så mange piksler (0: hele bildet, det var ikke større)
        let limit: CGFloat
        init(image: UIImage, tint: Color?, limit: CGFloat) { self.image = image; self.tint = tint; self.limit = limit }
    }

    private let cache = NSCache<NSURL, Entry>()
    private static let gate = DownloadGate(limit: 8)
    private let lock = NSLock()
    /// når en adresse som feilet, kan prøves igjen
    private var failed: [URL: Date] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 400 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    init() {
        cache.countLimit = 600
        // plakater og bakgrunnsbilder i full størrelse er store; de eldste glemmes og hentes fra disken igjen
        cache.totalCostLimit = 180 << 20
    }

    /// Bildet, når det er hentet og ikke er krympet mer enn [maxPixels] (nil: hent det).
    func cached(_ url: URL, maxPixels: CGFloat = Images.pixels(for: 180)) -> UIImage? {
        guard let entry = cache.object(forKey: url as NSURL) else { return nil }
        return entry.limit == 0 || entry.limit >= maxPixels ? entry.image : nil
    }

    /// Fargen bak logoen, når bildet er hentet (nil: ikke hentet ennå, eller standardflaten).
    func tint(for url: URL) -> Color? { cache.object(forKey: url as NSURL)?.tint }

    /// Bildet, høyst [maxPixels] bredt eller høyt (kanallogoene trenger ikke mer enn 180 punkter).
    func load(_ url: URL, maxPixels: CGFloat = Images.pixels(for: 180)) async -> UIImage? {
        if let image = cached(url, maxPixels: maxPixels) { return image }
        let waiting = lock.withLock { failed[url].map { Date() < $0 } ?? false }
        if waiting { return nil }
        var request = URLRequest(url: url)
        request.setValue(ProviderAgent.current, forHTTPHeaderField: "User-Agent")
        // høyst åtte om gangen (fra alle vertene): ruller du fort gjennom tusenvis av kanaler, ble det ellers like
        // mange forbindelser på en gang (som Fyrlys for Windows 2.1.45); de som er rullet forbi, slipper køen
        guard await Self.gate.enter() else { return nil }
        defer { Task { await Self.gate.leave() } }
        if Task.isCancelled { return nil }
        if let image = cached(url, maxPixels: maxPixels) { return image }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard status < 400, let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
            let largest = max(image.size.width, image.size.height, 1)
            let scale = min(1, maxPixels / largest)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let small = await image.byPreparingThumbnail(ofSize: size) ?? image
            let entry = Entry(image: small, tint: logoTint(small), limit: scale < 1 ? maxPixels : 0)
            cache.setObject(entry, forKey: url as NSURL, cost: Int(size.width * size.height * 4))
            lock.withLock { _ = failed.removeValue(forKey: url) }
            return small
        } catch {
            guard !Task.isCancelled else { return nil }
            let wait: TimeInterval
            switch (error as? URLError)?.code {
            case .cancelled?: return nil
            case .notConnectedToInternet?, .networkConnectionLost?, .timedOut?: wait = 30
            default: wait = 600
            }
            lock.withLock {
                if failed.count > 5000 { failed = failed.filter { $0.value > Date() } }
                failed[url] = Date().addingTimeInterval(wait)
            }
            return nil
        }
    }
}

/// Et bilde fra nettet, eller [fallback] mens det hentes og når det ikke finnes. [maxPoints] er det største bildet
/// vises (bredt eller høyt), så det hentes skarpt nok for skjermen uten å ta mer minne enn det må.
struct RemoteImage<Fallback: View>: View {
    let url: URL?
    /// fyll rammen (plakater), ellers hele bildet inni (logoer)
    var fill = false
    var maxPoints: CGFloat = 180
    @ViewBuilder let fallback: () -> Fallback
    @State private var image: UIImage?

    init(url: URL?, fill: Bool = false, maxPoints: CGFloat = 180, @ViewBuilder fallback: @escaping () -> Fallback) {
        self.url = url
        self.fill = fill
        self.maxPoints = maxPoints
        self.fallback = fallback
        _image = State(initialValue: url.flatMap { Images.shared.cached($0, maxPixels: Images.pixels(for: maxPoints)) })
    }

    var body: some View {
        Group {
            if let image {
                if fill {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            } else {
                fallback()
            }
        }
        .task(id: url) {
            guard let url, image == nil else { return }
            image = await Images.shared.load(url, maxPixels: Images.pixels(for: maxPoints))
        }
    }
}

/// Fargen bak en kanal: lik hver gang for samme kanal, dempet så logoene synes.
func channelTint(_ channel: Channel) -> Color {
    let hash = UInt64(stableHash(channel.id + channel.name), radix: 16) ?? 0
    return Color(hue: Double(hash % 360) / 360, saturation: 0.38, brightness: 0.30)
}

/// Logoflaten til en kanal: logoen, eller forbokstavene, på kanalens farge.
struct ChannelTile: View {
    let channel: Channel
    var favorite = false
    var compact = false

    var body: some View {
        let parts = nameParts(channel.name)
        ZStack {
            LinearGradient(colors: [channelTint(channel), Theme.logoBg], startPoint: .topLeading, endPoint: .bottomTrailing)
            RemoteImage(url: channel.logo.flatMap { URL(string: $0) }) {
                Text(verbatim: initials(channel.name))
                    .font(.system(size: compact ? 24 : 52, weight: .bold))
                    .foregroundStyle(Theme.ink.opacity(0.9))
            }
            .padding(compact ? 8 : 26)
            if !parts.time.isEmpty && !compact {
                Text(verbatim: parts.time)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.signal))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(12)
            }
            if favorite {
                Image(systemName: "star.fill")
                    .font(.system(size: compact ? 16 : 24))
                    .foregroundStyle(Theme.signal)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(compact ? 6 : 14)
                    .accessibilityIdentifier("favoritt-\(channel.id)")
            }
        }
    }
}

/// Høyst [limit] nedlastinger samtidig; de andre venter i kø. En som avbrytes mens den venter, går ut av køen.
actor DownloadGate {
    private let limit: Int
    private var running = 0
    private var waiting: [(id: UUID, resume: CheckedContinuation<Bool, Never>)] = []

    init(limit: Int) { self.limit = limit }

    /// Venter på plass; nei når oppgaven ble avbrutt i køen.
    func enter() async -> Bool {
        if running < limit {
            running += 1
            return true
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiting.append((id, continuation))
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func leave() {
        if waiting.isEmpty {
            running = max(0, running - 1)
        } else {
            // plassen går rett til den neste i køen
            waiting.removeFirst().resume.resume(returning: true)
        }
    }

    private func cancel(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).resume.resume(returning: false)
    }
}
