import TVServices

/// Apple TV's Top Shelf: when Webby is in the top row of the Home Screen, your favourite sites
/// appear above it, and selecting one opens it in Webby. Built from what the app last saved.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        completionHandler(content())
    }

    private func content() -> TVTopShelfContent? {
        guard let favorites = ShelfFavorites.load(), !favorites.items.isEmpty else { return nil }
        let folder = ShelfFavorites.imageFolder
        let items = favorites.items.enumerated().map { index, favorite -> TVTopShelfSectionedItem in
            let item = TVTopShelfSectionedItem(identifier: "\(index)-\(favorite.url.absoluteString)")
            item.title = favorite.title
            item.imageShape = .hdtv
            if let name = favorite.image, let file = folder?.appendingPathComponent(name) {
                item.setImageURL(file, for: .screenScale1x)
                item.setImageURL(file, for: .screenScale2x)
            }
            if let link = ShelfFavorites.openLink(for: favorite.url) {
                item.displayAction = TVTopShelfAction(url: link)
                item.playAction = TVTopShelfAction(url: link)
            }
            return item
        }
        let section = TVTopShelfItemCollection(items: items)
        section.title = "Favorites"
        return TVTopShelfSectionedContent(sections: [section])
    }
}
