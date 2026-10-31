import FyrlysCore
import SwiftUI
import UIKit

/// Logoene: hentes én gang (User-Agent som VLC, som leverandørene liker), gjøres små og tas vare på i minnet. En
/// adresse som ikke virket, prøves ikke igjen før etter ti minutter.
final class Images: @unchecked Sendable {
    static let shared = Images()

    private let cache = NSCache<NSURL, UIImage>()
    private let lock = NSLock()
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

    func cached(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL, maxPixels: CGFloat = 360) async -> UIImage? {
        if let image = cached(url) { return image }
        let recentlyFailed = lock.withLock { failed[url].map { Date().timeIntervalSince($0) < 600 } ?? false }
        if recentlyFailed { return nil }
        var request = URLRequest(url: url)
        request.setValue(xtreamUserAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard status < 400, let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
            let scale = min(1, maxPixels / max(image.size.width, image.size.height, 1))
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let small = await image.byPreparingThumbnail(ofSize: size) ?? image
            cache.setObject(small, forKey: url as NSURL)
            return small
        } catch {
            if !Task.isCancelled { lock.withLock { failed[url] = Date() } }
            return nil
        }
    }
}

/// Et bilde fra nettet, eller [fallback] mens det hentes og når det ikke finnes.
struct RemoteImage<Fallback: View>: View {
    let url: URL?
    @ViewBuilder let fallback: () -> Fallback
    @State private var image: UIImage?

    init(url: URL?, @ViewBuilder fallback: @escaping () -> Fallback) {
        self.url = url
        self.fallback = fallback
        _image = State(initialValue: url.flatMap { Images.shared.cached($0) })
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
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
            RemoteImage(url: channel.logo.flatMap(URL.init(string:))) {
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
