import Foundation
import TVServices

/// Top Shelf: når Fyrlys har fokus på hjemskjermen til Apple TV, vises favorittene øverst. Trykk spiller kanalen.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        let favorites = SharedFavorites.load()
        guard !favorites.isEmpty else {
            completionHandler(nil)
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
        let norsk = ["nb", "nn", "no"].contains(Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "")
        section.title = norsk ? "Favoritter" : "Favorites"
        completionHandler(TVTopShelfSectionedContent(sections: [section]))
    }
}
