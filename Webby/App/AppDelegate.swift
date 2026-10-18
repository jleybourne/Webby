//
//  AppDelegate.swift
//  Webby
//

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let settings = BrowserSettings.shared

        // A roomy shared cache makes repeat visits and back/forward near-instant.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024, diskPath: "WebbyCache")
        HTTPCookieStorage.shared.cookieAcceptPolicy = .onlyFromMainDocumentDomain
        ContentBlocker.install(enabled: settings.blockAds)
        settings.applyUserAgent()
        LibraryStore.shared.startCloudSync()
        TopShelfPublisher.shared.start(library: LibraryStore.shared)

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = BrowserViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    /// Top Shelf favourites open as `webbytv://open?url=…`.
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard let target = ShelfFavorites.target(of: url),
              let browser = window?.rootViewController as? BrowserViewController else { return false }
        browser.open(target)
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        LibraryStore.shared.saveNow()
        (window?.rootViewController as? BrowserViewController)?.tabManager.saveSession()
    }
}
