//
//  LibraryStore.swift
//  Webby
//
//  Bookmarks, favourites and history. Persisted as compact JSON in
//  UserDefaults (the persistent store available to tvOS apps). Bookmarks
//  also sync through iCloud key-value storage: whichever Apple TV changed
//  them last wins.
//

import Foundation
import Combine

struct Bookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var url: URL
    var isFavorite: Bool
    var dateAdded = Date()
}

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var url: URL
    var lastVisited: Date
    var visitCount: Int
}

final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var history: [HistoryEntry] = []

    private let defaults: UserDefaults
    private let cloud = NSUbiquitousKeyValueStore.default
    private var cloudObserver: NSObjectProtocol?
    private let maxHistory = 400
    private var saveWorkItem: DispatchWorkItem?

    private enum Keys {
        static let bookmarks = "library.bookmarks"
        static let history = "library.history"
        static let seeded = "library.seeded"
        /// When bookmarks were last changed on this Apple TV (or taken from iCloud).
        static let bookmarksModified = "library.bookmarksModified"
        static let cloudBookmarks = "bookmarks"
        static let cloudModified = "bookmarksModified"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bookmarks = Self.decode([Bookmark].self, from: defaults.data(forKey: Keys.bookmarks)) ?? []
        history = Self.decode([HistoryEntry].self, from: defaults.data(forKey: Keys.history)) ?? []
        if !defaults.bool(forKey: Keys.seeded) {
            defaults.set(true, forKey: Keys.seeded)
            if bookmarks.isEmpty { bookmarks = Self.starterFavorites; saveNow() }
        }
    }

    // MARK: Bookmarks

    var favorites: [Bookmark] { bookmarks.filter(\.isFavorite) }

    func isBookmarked(_ url: URL?) -> Bool {
        guard let url else { return false }
        return bookmarks.contains { $0.url.normalizedForComparison == url.normalizedForComparison }
    }

    func toggleBookmark(title: String, url: URL) {
        if let index = bookmarks.firstIndex(where: { $0.url.normalizedForComparison == url.normalizedForComparison }) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.insert(Bookmark(title: title.isEmpty ? URLResolver.displayHost(url) : title,
                                      url: url, isFavorite: true), at: 0)
        }
        bookmarksChanged()
    }

    func toggleFavorite(_ bookmark: Bookmark) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[index].isFavorite.toggle()
        bookmarksChanged()
    }

    func remove(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        bookmarksChanged()
    }

    func moveToFront(_ bookmark: Bookmark) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        let item = bookmarks.remove(at: index)
        bookmarks.insert(item, at: 0)
        bookmarksChanged()
    }

    // MARK: History

    func recordVisit(title: String, url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        let key = url.normalizedForComparison
        if let index = history.firstIndex(where: { $0.url.normalizedForComparison == key }) {
            var entry = history.remove(at: index)
            entry.lastVisited = Date()
            entry.visitCount += 1
            if !title.isEmpty { entry.title = title }
            entry.url = url
            history.insert(entry, at: 0)
        } else {
            history.insert(HistoryEntry(title: title, url: url, lastVisited: Date(), visitCount: 1), at: 0)
            if history.count > maxHistory { history.removeLast(history.count - maxHistory) }
        }
        scheduleSave()
    }

    func updateTitle(_ title: String, for url: URL) {
        guard !title.isEmpty,
              let index = history.firstIndex(where: { $0.url.normalizedForComparison == url.normalizedForComparison }),
              history[index].title != title else { return }
        history[index].title = title
        scheduleSave()
    }

    func remove(_ entry: HistoryEntry) {
        history.removeAll { $0.id == entry.id }
        scheduleSave()
    }

    func clearHistory() {
        history.removeAll()
        saveNow()
    }

    /// Most-visited sites, used for the start page's "Frequently Visited" row.
    var topSites: [HistoryEntry] {
        var seenHosts = Set<String>()
        return history
            .sorted { $0.visitCount == $1.visitCount ? $0.lastVisited > $1.lastVisited : $0.visitCount > $1.visitCount }
            .filter { seenHosts.insert($0.url.host ?? $0.url.absoluteString).inserted }
            .prefix(12)
            .map { $0 }
    }

    /// Local matches used by the address bar.
    func matches(for query: String, limit: Int = 8) -> [HistoryEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(history.prefix(limit)) }
        let bookmarkHits = bookmarks
            .filter { $0.title.lowercased().contains(q) || $0.url.absoluteString.lowercased().contains(q) }
            .map { HistoryEntry(id: $0.id, title: $0.title, url: $0.url, lastVisited: $0.dateAdded, visitCount: 1_000) }
        let historyHits = history.filter {
            $0.title.lowercased().contains(q) || $0.url.absoluteString.lowercased().contains(q)
        }
        var seen = Set<String>()
        return (bookmarkHits + historyHits)
            .filter { seen.insert($0.url.normalizedForComparison).inserted }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: iCloud

    func startCloudSync() {
        guard cloudObserver == nil else { return }
        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main
        ) { [weak self] _ in self?.pullFromCloud() }
        cloud.synchronize()
        syncWithCloud()
    }

    /// Takes iCloud's bookmarks if they're newer, otherwise shares this Apple TV's.
    func syncWithCloud() {
        pullFromCloud()
        if cloud.object(forKey: Keys.cloudModified) == nil
            || defaults.double(forKey: Keys.bookmarksModified) > cloud.double(forKey: Keys.cloudModified) {
            pushToCloud()
        }
    }

    private func bookmarksChanged() {
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.bookmarksModified)
        scheduleSave()
        pushToCloud()
    }

    private func pushToCloud() {
        guard BrowserSettings.shared.iCloudSync, let data = try? JSONEncoder().encode(bookmarks) else { return }
        cloud.set(data, forKey: Keys.cloudBookmarks)
        cloud.set(defaults.double(forKey: Keys.bookmarksModified), forKey: Keys.cloudModified)
        cloud.synchronize()
    }

    private func pullFromCloud() {
        guard BrowserSettings.shared.iCloudSync else { return }
        let remoteModified = cloud.double(forKey: Keys.cloudModified)
        guard remoteModified > defaults.double(forKey: Keys.bookmarksModified),
              let remote = Self.decode([Bookmark].self, from: cloud.data(forKey: Keys.cloudBookmarks)) else { return }
        bookmarks = remote
        defaults.set(remoteModified, forKey: Keys.bookmarksModified)
        saveNow()
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(bookmarks) { defaults.set(data, forKey: Keys.bookmarks) }
        if let data = try? encoder.encode(history) { defaults.set(data, forKey: Keys.history) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static let starterFavorites: [Bookmark] = [
        ("Google", "https://www.google.com"),
        ("YouTube", "https://www.youtube.com"),
        ("Wikipedia", "https://en.wikipedia.org"),
        ("Reddit", "https://www.reddit.com"),
        ("Hacker News", "https://news.ycombinator.com"),
        ("GitHub", "https://github.com"),
        ("BBC News", "https://www.bbc.com/news"),
        ("The Verge", "https://www.theverge.com"),
        ("Apple", "https://www.apple.com"),
        ("Weather", "https://weather.com"),
    ].compactMap { title, string in
        URL(string: string).map { Bookmark(title: title, url: $0, isFavorite: true) }
    }
}

extension URL {
    /// Scheme- and trailing-slash-insensitive key for de-duplicating URLs.
    var normalizedForComparison: String {
        var string = absoluteString.lowercased()
        for prefix in ["https://", "http://"] where string.hasPrefix(prefix) {
            string.removeFirst(prefix.count)
        }
        if string.hasPrefix("www.") { string.removeFirst(4) }
        while string.hasSuffix("/") { string.removeLast() }
        return string
    }
}
