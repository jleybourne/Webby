//
//  ShelfFavorites.swift
//  Webby (app and Top Shelf extension)
//
//  The favourites shown on the Apple TV Top Shelf. The app writes them, with a rendered tile
//  image for each, into the shared app group; the extension reads them.
//

import Foundation

struct ShelfFavorites: Codable {
    struct Item: Codable, Equatable {
        var title: String
        var url: URL
        /// File name of the tile image in `imageFolder`.
        var image: String?
    }

    var items: [Item]

    static let groupID = "group.app.webby"
    private static let key = "shelf.favorites"

    static var imageFolder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("Shelf", isDirectory: true)
    }

    static func load() -> ShelfFavorites? {
        guard let data = UserDefaults(suiteName: groupID)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ShelfFavorites.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.groupID)?.set(data, forKey: Self.key)
    }

    // MARK: Deep links

    /// The app's own URL scheme, used by Top Shelf items to open a site in Webby.
    static let urlScheme = "webbytv"

    static func openLink(for url: URL) -> URL? {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        return components.url
    }

    /// The website a `webbytv://open?url=…` link points at.
    static func target(of link: URL) -> URL? {
        guard link.scheme == urlScheme, link.host == "open",
              let value = URLComponents(url: link, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value,
              let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }
}
