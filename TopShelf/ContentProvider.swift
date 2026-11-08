import Foundation
import TVServices

/// Top Shelf: når Fyrlys har fokus på hjemskjermen til Apple TV, vises «Fortsett å se» og favorittene øverst. Trykk
/// på en kanal spiller den, på en film eller serie åpner siden for den.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        let favorites = SharedFavorites.load()
        let resume = SharedFavorites.loadResume()
        guard !favorites.isEmpty || !resume.isEmpty else {
            completionHandler(nil)
            return
        }
        let norsk = ["nb", "nn", "no"].contains(Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "")
        var sections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = []
        // «Fortsett å se» først, med bredbildet og streken for hvor langt du har kommet
        if !resume.isEmpty {
            let items: [TVTopShelfSectionedItem] = resume.prefix(20).map { entry in
                let item = TVTopShelfSectionedItem(identifier: "fortsett-\(entry.source ?? "iptv")-\(entry.id)")
                item.title = [entry.name, entry.episode].compactMap { $0 }.joined(separator: " · ")
                item.imageShape = .hdtv
                item.playbackProgress = entry.progress
                if let image = entry.image, let url = URL(string: image) {
                    item.setImageURL(url, for: .screenScale1x)
                    item.setImageURL(url, for: .screenScale2x)
                }
                if let url = SharedFavorites.url(entry) {
                    item.displayAction = TVTopShelfAction(url: url)
                    item.playAction = TVTopShelfAction(url: url)
                }
                return item
            }
            let section = TVTopShelfItemCollection(items: items)
            section.title = norsk ? "Fortsett å se" : "Continue watching"
            sections.append(section)
        }
        guard !favorites.isEmpty else {
            completionHandler(TVTopShelfSectionedContent(sections: sections))
            return
        }
        let items: [TVTopShelfSectionedItem] = favorites.prefix(30).map { favorite in
            let item = TVTopShelfSectionedItem(identifier: favorite.id)
            item.title = favorite.name
            item.imageShape = .hdtv
            if let logo = favorite.logo, let url = URL(string: logo) {
                item.setImageURL(url, for: .screenScale1x)
                item.setImageURL(url, for: .screenScale2x)
            }
            if let url = SharedFavorites.url(favorite.id) {
                item.displayAction = TVTopShelfAction(url: url)
                item.playAction = TVTopShelfAction(url: url)
            }
            return item
        }
        let section = TVTopShelfItemCollection(items: items)
        section.title = norsk ? "Favoritter" : "Favorites"
        sections.append(section)
        completionHandler(TVTopShelfSectionedContent(sections: sections))
    }
}
