//
//  TabManager.swift
//  Webby
//

import Foundation
import Combine

final class TabManager: ObservableObject {

    @Published private(set) var tabs: [BrowserTab] = []
    @Published private(set) var selectedID: UUID?

    /// Apple TV memory is tight; tabs beyond this many live engines are suspended.
    let maxLiveEngines = 4
    let maxTabs = 24

    private let defaults: UserDefaults
    private let settings = BrowserSettings.shared
    private var lruOrder: [UUID] = []

    private struct SavedTab: Codable { var id: UUID; var url: URL?; var title: String }
    private struct SavedSession: Codable { var tabs: [SavedTab]; var selected: UUID? }
    private static let sessionKey = "tabs.session"

    weak var tabDelegate: BrowserTabDelegate? {
        didSet { tabs.forEach { $0.delegate = tabDelegate } }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedTab: BrowserTab? {
        tabs.first { $0.id == selectedID } ?? tabs.first
    }

    var selectedIndex: Int? {
        guard let selectedTab else { return nil }
        return tabs.firstIndex { $0 === selectedTab }
    }

    // MARK: Session

    func restoreSession() {
        if settings.restoreTabs, !settings.privateBrowsing,
           let data = defaults.data(forKey: Self.sessionKey),
           let session = try? JSONDecoder().decode(SavedSession.self, from: data), !session.tabs.isEmpty {
            tabs = session.tabs.map { BrowserTab(id: $0.id, url: $0.url, title: $0.title) }
            tabs.forEach { $0.delegate = tabDelegate }
            selectedID = session.selected.flatMap { id in tabs.contains { $0.id == id } ? id : nil } ?? tabs.first?.id
        }
        if tabs.isEmpty {
            _ = newTab(url: settings.homePageURL, select: true)
        }
    }

    func saveSession() {
        guard !settings.privateBrowsing else {
            defaults.removeObject(forKey: Self.sessionKey)
            return
        }
        let session = SavedSession(tabs: tabs.map { SavedTab(id: $0.id, url: $0.url, title: $0.title) },
                                   selected: selectedID)
        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: Self.sessionKey)
        }
    }

    // MARK: Tabs

    @discardableResult
    func newTab(url: URL? = nil, select: Bool = true, after anchor: BrowserTab? = nil) -> BrowserTab {
        if tabs.count >= maxTabs, let oldest = tabs.first(where: { $0 !== selectedTab }) {
            close(oldest)
        }
        let tab = BrowserTab(url: url)
        tab.delegate = tabDelegate
        if let anchor, let index = tabs.firstIndex(where: { $0 === anchor }) {
            tabs.insert(tab, at: index + 1)
        } else {
            tabs.append(tab)
        }
        if select { self.select(tab) }
        saveSession()
        return tab
    }

    func select(_ tab: BrowserTab) {
        selectedTab?.captureSnapshot()
        selectedID = tab.id
        touch(tab)
        saveSession()
    }

    func close(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        let wasSelected = tab.id == selectedID
        tab.stop()
        tab.webView?.removeFromSuperview()
        tabs.remove(at: index)
        lruOrder.removeAll { $0 == tab.id }
        if tabs.isEmpty {
            newTab(url: nil, select: true)
            return
        }
        if wasSelected {
            let next = tabs[min(index, tabs.count - 1)]
            select(next)
        }
        saveSession()
    }

    func closeAll() {
        tabs.forEach { $0.stop(); $0.webView?.removeFromSuperview() }
        tabs.removeAll()
        lruOrder.removeAll()
        newTab(url: nil, select: true)
    }

    func selectNext(offset: Int) {
        guard let index = selectedIndex, tabs.count > 1 else { return }
        let next = (index + offset + tabs.count) % tabs.count
        select(tabs[next])
    }

    func rebuildAllEngines() {
        tabs.forEach { $0.rebuildWebView() }
    }

    /// Keeps only the most recently used tabs' engines alive.
    private func touch(_ tab: BrowserTab) {
        lruOrder.removeAll { $0 == tab.id }
        lruOrder.insert(tab.id, at: 0)
        guard lruOrder.count > maxLiveEngines else { return }
        for id in lruOrder.dropFirst(maxLiveEngines) {
            tabs.first { $0.id == id }?.suspend()
        }
        lruOrder = Array(lruOrder.prefix(maxLiveEngines))
    }
}
