//
//  BrowserSettings.swift
//  Webby
//

import Foundation
import Combine

enum SearchEngine: String, CaseIterable, Identifiable, Codable {
    case google, duckDuckGo, bing, brave, ecosia

    var id: String { rawValue }

    var name: String {
        switch self {
        case .google: return "Google"
        case .duckDuckGo: return "DuckDuckGo"
        case .bing: return "Bing"
        case .brave: return "Brave Search"
        case .ecosia: return "Ecosia"
        }
    }

    func searchURL(for query: String) -> URL {
        let q = query.addingPercentEncoding(withAllowedCharacters: .webbyQueryAllowed) ?? query
        let string: String
        switch self {
        case .google: string = "https://www.google.com/search?q=\(q)"
        case .duckDuckGo: string = "https://duckduckgo.com/?q=\(q)"
        case .bing: string = "https://www.bing.com/search?q=\(q)"
        case .brave: string = "https://search.brave.com/search?q=\(q)"
        case .ecosia: string = "https://www.ecosia.org/search?q=\(q)"
        }
        return URL(string: string) ?? URL(string: "https://duckduckgo.com")!
    }
}

enum UserAgentMode: String, CaseIterable, Identifiable, Codable {
    case desktop, iPad, iPhone, appleTV

    var id: String { rawValue }

    var name: String {
        switch self {
        case .desktop: return "Desktop (Mac Safari)"
        case .iPad: return "iPad"
        case .iPhone: return "iPhone"
        case .appleTV: return "Apple TV (default)"
        }
    }

    var shortName: String {
        switch self {
        case .desktop: return "Desktop"
        case .iPad: return "iPad"
        case .iPhone: return "Mobile"
        case .appleTV: return "Apple TV"
        }
    }

    var userAgent: String? {
        switch self {
        case .desktop:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        case .iPad:
            return "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        case .iPhone:
            return "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        case .appleTV:
            return nil
        }
    }
}

final class BrowserSettings: ObservableObject {
    static let shared = BrowserSettings()

    private let defaults: UserDefaults

    @Published var searchEngine: SearchEngine { didSet { defaults.set(searchEngine.rawValue, forKey: Keys.searchEngine) } }
    @Published var userAgentMode: UserAgentMode {
        didSet {
            defaults.set(userAgentMode.rawValue, forKey: Keys.userAgent)
            applyUserAgent()
        }
    }
    @Published var homePage: String { didSet { defaults.set(homePage, forKey: Keys.homePage) } }
    @Published var blockAds: Bool {
        didSet {
            defaults.set(blockAds, forKey: Keys.blockAds)
            ContentBlocker.isEnabled = blockAds
        }
    }
    @Published var privateBrowsing: Bool { didSet { defaults.set(privateBrowsing, forKey: Keys.privateBrowsing) } }
    @Published var restoreTabs: Bool { didSet { defaults.set(restoreTabs, forKey: Keys.restoreTabs) } }
    @Published var openPopupsInNewTab: Bool { didSet { defaults.set(openPopupsInNewTab, forKey: Keys.popups) } }
    @Published var cursorSpeed: Double { didSet { defaults.set(cursorSpeed, forKey: Keys.cursorSpeed) } }
    @Published var scrollSpeed: Double { didSet { defaults.set(scrollSpeed, forKey: Keys.scrollSpeed) } }
    @Published var edgeScrolling: Bool { didSet { defaults.set(edgeScrolling, forKey: Keys.edgeScrolling) } }
    @Published var defaultZoom: Double { didSet { defaults.set(defaultZoom, forKey: Keys.defaultZoom) } }
    @Published var showHints: Bool { didSet { defaults.set(showHints, forKey: Keys.showHints) } }
    @Published var darkPages: Bool { didSet { defaults.set(darkPages, forKey: Keys.darkPages) } }
    @Published var iCloudSync: Bool { didSet { defaults.set(iCloudSync, forKey: Keys.iCloudSync) } }
    /// Zoom chosen for each site (keyed by display host), applied whenever that site loads.
    @Published private(set) var siteZooms: [String: Double] { didSet { defaults.set(siteZooms, forKey: Keys.siteZooms) } }

    private enum Keys {
        static let searchEngine = "settings.searchEngine"
        static let userAgent = "settings.userAgent"
        static let homePage = "settings.homePage"
        static let blockAds = "settings.blockAds"
        static let privateBrowsing = "settings.privateBrowsing"
        static let restoreTabs = "settings.restoreTabs"
        static let popups = "settings.popups"
        static let cursorSpeed = "settings.cursorSpeed"
        static let scrollSpeed = "settings.scrollSpeed"
        static let edgeScrolling = "settings.edgeScrolling"
        static let defaultZoom = "settings.defaultZoom"
        static let showHints = "settings.showHints"
        static let darkPages = "settings.darkPages"
        static let iCloudSync = "settings.iCloudSync"
        static let siteZooms = "settings.siteZooms"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.searchEngine: SearchEngine.google.rawValue,
            Keys.userAgent: UserAgentMode.desktop.rawValue,
            Keys.homePage: "",
            Keys.blockAds: true,
            Keys.privateBrowsing: false,
            Keys.restoreTabs: true,
            Keys.popups: true,
            Keys.cursorSpeed: 1.6,
            Keys.scrollSpeed: 1.4,
            Keys.edgeScrolling: true,
            Keys.defaultZoom: 1.0,
            Keys.showHints: true,
            Keys.darkPages: false,
            Keys.iCloudSync: true,
        ])
        searchEngine = SearchEngine(rawValue: defaults.string(forKey: Keys.searchEngine) ?? "") ?? .google
        userAgentMode = UserAgentMode(rawValue: defaults.string(forKey: Keys.userAgent) ?? "") ?? .desktop
        homePage = defaults.string(forKey: Keys.homePage) ?? ""
        blockAds = defaults.bool(forKey: Keys.blockAds)
        privateBrowsing = defaults.bool(forKey: Keys.privateBrowsing)
        restoreTabs = defaults.bool(forKey: Keys.restoreTabs)
        openPopupsInNewTab = defaults.bool(forKey: Keys.popups)
        cursorSpeed = defaults.double(forKey: Keys.cursorSpeed)
        scrollSpeed = defaults.double(forKey: Keys.scrollSpeed)
        edgeScrolling = defaults.bool(forKey: Keys.edgeScrolling)
        defaultZoom = defaults.double(forKey: Keys.defaultZoom)
        showHints = defaults.bool(forKey: Keys.showHints)
        darkPages = defaults.bool(forKey: Keys.darkPages)
        iCloudSync = defaults.bool(forKey: Keys.iCloudSync)
        siteZooms = defaults.dictionary(forKey: Keys.siteZooms) as? [String: Double] ?? [:]
    }

    func zoom(for url: URL?) -> Double {
        guard let url, url.host != nil else { return defaultZoom }
        return siteZooms[URLResolver.displayHost(url)] ?? defaultZoom
    }

    /// Remembers a site's zoom; going back to the default forgets it. Nothing is kept in Private Browsing.
    func setZoom(_ zoom: Double, for url: URL?) {
        guard !privateBrowsing, let url, url.host != nil else { return }
        let host = URLResolver.displayHost(url)
        if abs(zoom - defaultZoom) < 0.01 { siteZooms[host] = nil } else { siteZooms[host] = zoom }
    }

    /// The legacy engine reads its user agent from the registration domain when a web view is created.
    func applyUserAgent() {
        if let ua = userAgentMode.userAgent {
            UserDefaults.standard.register(defaults: ["UserAgent": ua])
            didRegisterUserAgent = true
        } else if didRegisterUserAgent {
            UserDefaults.standard.register(defaults: ["UserAgent": Self.systemUserAgentPlaceholder])
        }
    }

    private var didRegisterUserAgent = false

    /// Used when switching back to the system UA: an Apple TV-flavoured Safari string.
    static let systemUserAgentPlaceholder =
        "Mozilla/5.0 (Apple TV; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/604.1"

    var homePageURL: URL? {
        let trimmed = homePage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URLResolver.url(from: trimmed, engine: searchEngine)
    }
}

extension CharacterSet {
    static let webbyQueryAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=?#")
        return set
    }()
}

enum URLResolver {
    /// Turns whatever the user typed into a URL: a full URL, a bare domain, or a search.
    static func url(from input: String, engine: SearchEngine) -> URL {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return engine.searchURL(for: "") }

        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           ["http", "https", "about", "data", "file"].contains(scheme) {
            return url
        }

        if !text.contains(" "), looksLikeHost(text) {
            let prefix = text.hasPrefix("localhost") || isIPAddress(text) ? "http://" : "https://"
            if let url = URL(string: prefix + text) { return url }
        }
        return engine.searchURL(for: text)
    }

    private static func looksLikeHost(_ text: String) -> Bool {
        let hostPart = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? text
        if hostPart.hasPrefix("localhost") { return true }
        if isIPAddress(text) { return true }
        let host = hostPart.split(separator: ":").first.map(String.init) ?? hostPart
        let labels = host.split(separator: ".")
        guard labels.count >= 2, let tld = labels.last, tld.count >= 2 else { return false }
        return tld.allSatisfy { $0.isLetter } && labels.allSatisfy { !$0.isEmpty }
    }

    private static func isIPAddress(_ text: String) -> Bool {
        let hostPart = text.split(separator: "/").first.map(String.init) ?? text
        let host = hostPart.split(separator: ":").first.map(String.init) ?? hostPart
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }

    /// A short, human-friendly host for display (drops "www.").
    static func displayHost(_ url: URL?) -> String {
        guard let host = url?.host else { return url?.absoluteString ?? "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
