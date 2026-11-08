import ImageIO
import SwiftUI
import UIKit
import WidgetKit

/// Widgeten på hjemskjermen til iPhone og iPad: favorittkanalene med logo (som Top Shelf på Apple TV). Trykk på en
/// kanal åpner Fyrlys og spiller den (fyrlys://kanal/<id>). Appen skriver favorittene i den felles nøkkelring-gruppen
/// når de endres.
@main
struct FyrlysWidgetBundle: WidgetBundle {
    var body: some Widget {
        FavoritesWidget()
    }
}

struct FavoritesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "favoritter", provider: FavoritesProvider()) { entry in
            FavoritesView(entry: entry)
                .containerBackground(for: .widget) { WidgetTheme.bg }
        }
        .configurationDisplayName(appIsNorwegian ? "Favoritter" : "Favourites")
        .description(appIsNorwegian ? "Favorittkanalene dine. Trykk for å se." : "Your favourite channels. Tap to watch.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// Språket på enheten (appen er på norsk for nb/nn/no, ellers engelsk).
let appIsNorwegian: Bool = {
    let code = Locale.preferredLanguages.first?.prefix(2) ?? "en"
    return ["nb", "nn", "no"].contains(String(code))
}()

enum WidgetTheme {
    static let bg = Color(red: 0.039, green: 0.075, blue: 0.118)
    static let tile = Color(red: 0.086, green: 0.137, blue: 0.196)
    static let ink = Color(red: 0.93, green: 0.95, blue: 0.97)
    static let muted = Color(red: 0.6, green: 0.66, blue: 0.73)
    static let signal = Color(red: 0.96, green: 0.71, blue: 0.27)
}

struct FavoriteChannel: Identifiable {
    let id: String
    let name: String
    let logo: UIImage?
}

struct FavoritesEntry: TimelineEntry {
    let date: Date
    let channels: [FavoriteChannel]
}

struct FavoritesProvider: TimelineProvider {
    func placeholder(in context: Context) -> FavoritesEntry {
        FavoritesEntry(date: Date(), channels: ["NRK1", "NRK2", "TV 2", "NRK3"].enumerated().map {
            FavoriteChannel(id: "\($0.offset)", name: $0.element, logo: nil)
        })
    }

    func getSnapshot(in context: Context, completion: @escaping (FavoritesEntry) -> Void) {
        Task { completion(await load(limit: limit(context.family))) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FavoritesEntry>) -> Void) {
        Task {
            let entry = await load(limit: limit(context.family))
            // appen sier fra når favorittene endres; ellers en gang i døgnet (logoene)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(24 * 3600))))
        }
    }

    private func limit(_ family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: return 1
        case .systemMedium: return 4
        default: return 8
        }
    }

    private func load(limit: Int) async -> FavoritesEntry {
        let favorites = Array(SharedFavorites.load().prefix(limit))
        var channels: [FavoriteChannel] = []
        await withTaskGroup(of: (Int, UIImage?).self) { group in
            for (index, favorite) in favorites.enumerated() {
                group.addTask { (index, await Self.logo(favorite.logo)) }
            }
            var logos: [Int: UIImage] = [:]
            for await (index, image) in group { logos[index] = image }
            channels = favorites.enumerated().map {
                FavoriteChannel(id: $0.element.id, name: $0.element.name, logo: logos[$0.offset])
            }
        }
        return FavoritesEntry(date: Date(), channels: channels)
    }

    /// Logoen krympet til 180 piksler (widgeten har lite minne).
    private static func logo(_ address: String?) async -> UIImage? {
        guard let address, let url = URL(string: address) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.setValue("VLC/3.0.20 LibVLC/3.0.20", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 180,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

struct FavoritesView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FavoritesEntry

    var body: some View {
        if entry.channels.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "star")
                    .font(.title2)
                    .foregroundStyle(WidgetTheme.signal)
                Text(appIsNorwegian ? "Legg til favoritter i Fyrlys" : "Add favourites in Fyrlys")
                    .font(.caption)
                    .foregroundStyle(WidgetTheme.muted)
                    .multilineTextAlignment(.center)
            }
        } else if family == .systemSmall, let channel = entry.channels.first {
            VStack(spacing: 8) {
                tile(channel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(channel.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
            }
            .widgetURL(link(channel))
        } else {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(entry.channels) { channel in
                    Link(destination: link(channel)) {
                        VStack(spacing: 5) {
                            tile(channel)
                                .aspectRatio(4 / 3, contentMode: .fit)
                            Text(channel.name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(WidgetTheme.ink)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: family == .systemLarge ? .top : .center)
        }
    }

    private func tile(_ channel: FavoriteChannel) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(WidgetTheme.tile)
            .overlay {
                if let logo = channel.logo {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                } else {
                    Text(String(channel.name.prefix(3)))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WidgetTheme.ink.opacity(0.7))
                }
            }
    }

    private func link(_ channel: FavoriteChannel) -> URL {
        URL(string: "fyrlys://kanal/\(channel.id)") ?? URL(string: "fyrlys://")!
    }
}
