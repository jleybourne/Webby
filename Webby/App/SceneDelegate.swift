//
//  SceneDelegate.swift
//  Webby
//
//  Owns the window. tvOS 27 makes "no scene lifecycle adoption" a fatal UIKit runtime issue
//  (`UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption`), so the window can no longer be
//  built in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
//

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    /// The browser, for the one place outside the scene that needs it: saving the session when the
    /// app terminates. tvOS only ever has the one scene.
    static weak var browser: BrowserViewController?

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let browser = BrowserViewController()
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = browser
        window.makeKeyAndVisible()
        self.window = window
        SceneDelegate.browser = browser

        // A Top Shelf tile launches the app with its link in the connection options; once the app is
        // running the same links arrive in `scene(_:openURLContexts:)` below.
        for context in connectionOptions.urlContexts {
            open(context.url)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            open(context.url)
        }
    }

    /// Top Shelf favourites open as `webbytv://open?url=…`.
    private func open(_ url: URL) {
        guard let target = ShelfFavorites.target(of: url),
              let browser = SceneDelegate.browser else { return }
        browser.open(target)
    }
}
