//
//  TopShelfPublisher.swift
//  Webby
//
//  Keeps the Top Shelf in step with your favourites: renders a tile for each one into the
//  shared app group and tells tvOS the shelf changed.
//

import SwiftUI
import Combine
import TVServices

@MainActor
final class TopShelfPublisher {
    static let shared = TopShelfPublisher()

    private var cancellable: AnyCancellable?
    private var publishTask: Task<Void, Never>?
    private let maxItems = 12

    func start(library: LibraryStore) {
        cancellable = library.$bookmarks
            .map { [maxItems] bookmarks in
                bookmarks.filter(\.isFavorite).prefix(maxItems).map { ShelfFavorites.Item(title: $0.title, url: $0.url) }
            }
            .removeDuplicates()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] items in self?.publish(items) }
    }

    private func publish(_ items: [ShelfFavorites.Item]) {
        publishTask?.cancel()
        publishTask = Task { [weak self] in
            guard let folder = ShelfFavorites.imageFolder else { return }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var published: [ShelfFavorites.Item] = []
            for var item in items {
                let name = Self.fileName(for: item.url)
                let file = folder.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: file.path) {
                    let icon = await Self.favicon(for: item.url)
                    guard !Task.isCancelled else { return }
                    if let png = self?.renderTile(for: item.url, icon: icon) { try? png.write(to: file) }
                }
                if FileManager.default.fileExists(atPath: file.path) { item.image = name }
                published.append(item)
            }
            guard !Task.isCancelled else { return }
            Self.removeUnused(in: folder, keeping: Set(published.compactMap(\.image)))
            ShelfFavorites(items: published).save()
            TVTopShelfContentProvider.topShelfContentDidChange()
        }
    }

    private func renderTile(for url: URL, icon: UIImage?) -> Data? {
        let renderer = ImageRenderer(content: ShelfTile(host: URLResolver.displayHost(url), icon: icon))
        renderer.scale = 1
        return renderer.uiImage?.pngData()
    }

    private static func favicon(for url: URL) async -> UIImage? {
        guard let host = url.host,
              let iconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=256") else { return nil }
        var request = URLRequest(url: iconURL)
        request.timeoutInterval = 5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return UIImage(data: data)
    }

    /// Stable per site, so tiles are only rendered once.
    private static func fileName(for url: URL) -> String {
        let hash = url.normalizedForComparison.unicodeScalars.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1.value) }
        return String(hash, radix: 16) + ".png"
    }

    private static func removeUnused(in folder: URL, keeping names: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for file in files where !names.contains(file) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }
}

/// A 16:9 Top Shelf tile: the site's colour with its icon in a white rounded square.
private struct ShelfTile: View {
    let host: String
    let icon: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.color(for: host).gradient)
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
            RoundedRectangle(cornerRadius: 56, style: .continuous)
                .fill(.white)
                .frame(width: 240, height: 240)
                .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
            if let icon {
                Image(uiImage: icon).resizable().interpolation(.high).scaledToFit().frame(width: 150, height: 150)
            } else {
                Text(String(host.first ?? "W").uppercased())
                    .font(.system(size: 130, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.color(for: host))
            }
        }
        .frame(width: 800, height: 450)
    }
}
