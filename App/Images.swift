import FyrlysCore
import SwiftUI
import UIKit

/// Logoene: hentes én gang (User-Agent som VLC, som leverandørene liker), gjøres små og tas vare på i minnet sammen
/// med fargen bak dem. En adresse som svarte med en feil eller ikke var et bilde, prøves ikke igjen før etter ti
/// minutter; var nettet borte eller tok det for lang tid, prøves den igjen etter et halvt minutt.
final class Images: @unchecked Sendable {
    static let shared = Images()

    /// bildet og bakgrunnsfargen bak det (de store kortene), regnet ut én gang; sammen, så fargen ikke blir borte
    /// fra et bilde som fortsatt er i minnet
    private final class Logo {
        let image: UIImage
        let tint: Color?
        init(image: UIImage, tint: Color?) { self.image = image; self.tint = tint }
    }

    private let cache = NSCache<NSURL, Logo>()
    private let lock = NSLock()
    /// når en adresse som feilet, kan prøves igjen
    private var failed: [URL: Date] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 150 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    init() { cache.countLimit = 600 }

    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL)?.image }

    /// Fargen bak logoen, når bildet er hentet (nil: ikke hentet ennå, eller standardflaten).
    func tint(for url: URL) -> Color? { cache.object(forKey: url as NSURL)?.tint }

    func load(_ url: URL, maxPixels: CGFloat = 360) async -> UIImage? {
        if let image = cached(url) { return image }
        let waiting = lock.withLock { failed[url].map { Date() < $0 } ?? false }
        if waiting { return nil }
        var request = URLRequest(url: url)
        request.setValue(xtreamUserAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard status < 400, let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
            let scale = min(1, maxPixels / max(image.size.width, image.size.height, 1))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let small = await image.byPreparingThumbnail(ofSize: size) ?? image
            cache.setObject(Logo(image: small, tint: logoTint(small)), forKey: url as NSURL)
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

/// Et bilde fra nettet, eller [fallback] mens det hentes og når det ikke finnes.
struct RemoteImage<Fallback: View>: View {
    let url: URL?
    /// fyll rammen (plakater), ellers hele bildet inni (logoer)
    var fill = false
    @ViewBuilder let fallback: () -> Fallback
    @State private var image: UIImage?

    init(url: URL?, fill: Bool = false, @ViewBuilder fallback: @escaping () -> Fallback) {
        self.url = url
        self.fill = fill
        self.fallback = fallback
        _image = State(initialValue: url.flatMap { Images.shared.cached($0) })
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
            image = await Images.shared.load(url)
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
