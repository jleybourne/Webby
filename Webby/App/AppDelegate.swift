//
//  AppDelegate.swift
//  Webby
//

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

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

        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        LibraryStore.shared.saveNow()
        SceneDelegate.browser?.tabManager.saveSession()
    }
}
