//
//  BrowserViewController.swift
//  Webby
//
//  The heart of Webby: hosts the active tab's engine, turns Siri Remote touches
//  into a pointer or inertial scrolling, and presents the SwiftUI chrome.
//
//  Remote controls
//    • Swipe            move the pointer (Cursor mode) or scroll (Scroll mode)
//    • Click            click whatever is under the pointer
//    • Click & hold     toggle Cursor / Scroll mode
//    • Play/Pause       open the Webby menu
//    • Menu / Back      go back (or leave Scroll mode / return from the start page)
//    • D-pad edges      page up / down / left / right
//

import UIKit
import SwiftUI
import AVKit
import Combine

enum InputMode {
    case cursor, scroll

    var label: String { self == .cursor ? "Cursor" : "Scroll" }
}

/// Invisible, focusable layer that receives Siri Remote touches and presses while a page is shown.
final class RemoteSurfaceView: UIView {
    override var canBecomeFocused: Bool { true }
}

final class BrowserViewController: UIViewController {

    let tabManager = TabManager()
    private let settings = BrowserSettings.shared
    private let library = LibraryStore.shared

    private let webContainer = UIView()
    private let surface = RemoteSurfaceView()
    private let cursor = CursorView()
    private let hud = StatusHUDView()
    private let toast = ToastView()
    private let progressBar = UIProgressView(progressViewStyle: .default)
    private var startPageHost: UIHostingController<StartPageView>?

    private(set) var mode: InputMode = .cursor
    private var cancellables = Set<AnyCancellable>()
    private var tabCancellables = Set<AnyCancellable>()
    private weak var observedTab: BrowserTab?
    private var lastHUDKey = ""
    private var lastShownError: String?
    /// Kept so Picture in Picture can bring the full-screen player back.
    private var playerController: AVPlayerViewController?

    // Touch & motion state
    private var lastTouchPoint: CGPoint?
    private var lastTouchTimestamp: TimeInterval = 0
    private var lastMoveTime: CFTimeInterval = 0
    private var isTouching = false
    private var scrollVelocity: CGPoint = .zero
    private var displayLink: CADisplayLink?
    private var hoverNeedsCheck = false
    private var lastHoverCheck: CFTimeInterval = 0
    private var consumedPresses = Set<UIPress.PressType>()

    private lazy var selectTap: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleSelectTap))
        tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        tap.allowedTouchTypes = []
        return tap
    }()

    private lazy var selectHold: UILongPressGestureRecognizer = {
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleSelectHold(_:)))
        hold.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        hold.allowedTouchTypes = []
        hold.minimumPressDuration = 0.55
        return hold
    }()

    private lazy var playPauseTap: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handlePlayPause))
        tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
        tap.allowedTouchTypes = []
        return tap
    }()

    private var currentTab: BrowserTab? { tabManager.selectedTab }
    private var isStartPageVisible: Bool { startPageHost != nil }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        webContainer.frame = view.bounds
        webContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webContainer.backgroundColor = .black
        view.addSubview(webContainer)

        surface.frame = view.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        surface.backgroundColor = .clear
        view.addSubview(surface)

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.progressTintColor = .systemBlue
        progressBar.trackTintColor = .clear
        progressBar.alpha = 0
        view.addSubview(progressBar)

        hud.translatesAutoresizingMaskIntoConstraints = false
        hud.alpha = 0
        view.addSubview(hud)

        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)

        cursor.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        view.addSubview(cursor)

        NSLayoutConstraint.activate([
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressBar.topAnchor.constraint(equalTo: view.topAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 6),
            hud.topAnchor.constraint(equalTo: view.topAnchor, constant: 36),
            hud.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hud.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.7),
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -110),
        ])

        selectTap.require(toFail: selectHold)
        surface.addGestureRecognizer(selectTap)
        surface.addGestureRecognizer(selectHold)
        view.addGestureRecognizer(playPauseTap)

        tabManager.tabDelegate = self
        tabManager.$selectedID
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.displaySelectedTab() }
            .store(in: &cancellables)

        settings.$userAgentMode
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                guard let self else { return }
                self.tabManager.rebuildAllEngines()
                self.displaySelectedTab()
                self.toast.show("Requesting \(mode.shortName) sites")
            }
            .store(in: &cancellables)

        settings.$darkPages
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] on in
                self?.tabManager.tabs.forEach { $0.applyDarkPages(on) }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.applicationDidEnterBackground() }
            .store(in: &cancellables)

        tabManager.restoreSession()

        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !WBWebView.isEngineAvailable {
            presentEngineUnavailableAlert()
        } else if settings.showHints {
            settings.showHints = false
            presentPanel(ControlsGuideView(dismiss: { [weak self] in self?.dismiss(animated: true) }))
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        for tab in tabManager.tabs where tab !== currentTab { tab.suspend() }
        URLCache.shared.removeAllCachedResponses()
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if let host = startPageHost { return [host.view] }
        return [surface]
    }

    private func applicationDidEnterBackground() {
        tabManager.saveSession()
        library.saveNow()
        if settings.privateBrowsing { DataCleaner.clearWebsiteData() }
    }

    // MARK: Tab display

    private func displaySelectedTab() {
        guard let tab = currentTab else { return }
        if observedTab !== tab {
            observedTab = tab
            tabCancellables.removeAll()
            tab.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.syncContent() }
                .store(in: &tabCancellables)
            for subview in webContainer.subviews where subview !== tab.webView {
                subview.removeFromSuperview()
            }
            lastHUDKey = ""
        }
        syncContent()
    }

    /// Reconciles what's on screen (engine vs. start page, chrome) with the current tab's state.
    private func syncContent() {
        guard let tab = currentTab else { return }

        if tab.isStartPage {
            setStartPageVisible(true)
        } else {
            let webView = tab.makeWebViewIfNeeded()
            if webView.superview !== webContainer {
                webContainer.subviews.forEach { $0.removeFromSuperview() }
                webView.frame = webContainer.bounds
                webContainer.addSubview(webView)
            }
            setStartPageVisible(false)
        }

        // Progress bar
        if tab.isLoading {
            progressBar.alpha = 1
            progressBar.setProgress(Float(tab.progress), animated: true)
        } else if progressBar.alpha > 0 {
            progressBar.setProgress(1, animated: true)
            UIView.animate(withDuration: 0.35, delay: 0.15, options: []) { self.progressBar.alpha = 0 } completion: { _ in
                if !(self.currentTab?.isLoading ?? false) { self.progressBar.setProgress(0, animated: false) }
            }
        }

        // HUD
        hud.update(url: tab.url, isLoading: tab.isLoading, blocked: tab.blockedCount, mode: mode.label)
        let key = "\(tab.url?.host ?? "")|\(tab.isLoading)|\(mode)"
        if key != lastHUDKey, !isStartPageVisible {
            lastHUDKey = key
            hud.flash(keepVisible: tab.isLoading)
        }
        if isStartPageVisible { hud.alpha = 0 }

        if let error = tab.lastError, error != lastShownError {
            lastShownError = error
            toast.show(error, duration: 3)
        } else if tab.lastError == nil {
            lastShownError = nil
        }
    }

    private func setStartPageVisible(_ visible: Bool) {
        guard visible != isStartPageVisible else { return }
        if visible {
            let host = UIHostingController(rootView: StartPageView(
                library: library,
                settings: settings,
                tabCount: tabManager.tabs.count,
                onOpen: { [weak self] url in self?.currentTab?.load(url) },
                onSearch: { [weak self] in self?.presentSearch() },
                onAction: { [weak self] action in self?.run(action) }
            ))
            host.view.backgroundColor = .clear
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addChild(host)
            view.insertSubview(host.view, aboveSubview: surface)
            host.didMove(toParent: self)
            host.view.alpha = 0
            UIView.animate(withDuration: 0.25) { host.view.alpha = 1 }
            startPageHost = host
            cursor.isHidden = true
            hud.alpha = 0
        } else if let host = startPageHost {
            startPageHost = nil
            host.willMove(toParent: nil)
            UIView.animate(withDuration: 0.2, animations: { host.view.alpha = 0 }) { _ in
                host.view.removeFromSuperview()
                host.removeFromParent()
            }
            cursor.isHidden = mode == .scroll
        }
        selectTap.isEnabled = !visible
        selectHold.isEnabled = !visible
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    // MARK: Modes

    private func setMode(_ newMode: InputMode, announce: Bool = true) {
        guard newMode != mode else { return }
        mode = newMode
        scrollVelocity = .zero
        UIView.animate(withDuration: 0.2) {
            self.cursor.alpha = newMode == .cursor ? 1 : 0
        }
        cursor.isHidden = isStartPageVisible
        if announce {
            toast.show(newMode == .cursor ? "Cursor Mode" : "Scroll Mode — swipe to scroll")
        }
        syncContent()
    }

    // MARK: Remote input — presses

    @objc private func handleSelectTap() {
        guard !isStartPageVisible else { return }
        if mode == .scroll {
            setMode(.cursor)
            return
        }
        performClick()
    }

    @objc private func handleSelectHold(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !isStartPageVisible else { return }
        setMode(mode == .cursor ? .scroll : .cursor)
    }

    @objc private func handlePlayPause() {
        if presentedViewController == nil { presentMenu() }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let press = presses.first, presentedViewController == nil else {
            super.pressesBegan(presses, with: event)
            return
        }
        if handlePress(press.type) {
            consumedPresses.insert(press.type)
        } else {
            super.pressesBegan(presses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let press = presses.first, consumedPresses.remove(press.type) != nil { return }
        super.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if let press = presses.first, consumedPresses.remove(press.type) != nil { return }
        super.pressesCancelled(presses, with: event)
    }

    /// Returns true when Webby handled the press (so Menu doesn't exit the app).
    private func handlePress(_ type: UIPress.PressType) -> Bool {
        guard let tab = currentTab else { return false }
        switch type {
        case .menu:
            if isStartPageVisible {
                return tab.resumeFromStartPage()
            }
            if mode == .scroll { setMode(.cursor); return true }
            if tab.canGoBack || tab.webView?.canGoBack == true { tab.goBack(); return true }
            if tabManager.tabs.count > 1 { tabManager.close(tab); toast.show("Closed Tab"); return true }
            if !tab.isStartPage { tab.showStartPage(); return true }
            return false
        case .upArrow, .downArrow, .leftArrow, .rightArrow, .pageUp, .pageDown:
            guard !isStartPageVisible, let scrollView = tab.webView?.scrollView else { return false }
            let page = scrollView.bounds.size
            let delta: CGPoint
            switch type {
            case .upArrow: delta = CGPoint(x: 0, y: -page.height * 0.6)
            case .downArrow: delta = CGPoint(x: 0, y: page.height * 0.6)
            case .pageUp: delta = CGPoint(x: 0, y: -page.height * 0.9)
            case .pageDown: delta = CGPoint(x: 0, y: page.height * 0.9)
            case .leftArrow: delta = CGPoint(x: -page.width * 0.5, y: 0)
            default: delta = CGPoint(x: page.width * 0.5, y: 0)
            }
            scroll(by: delta, animated: true)
            return true
        default:
            return false
        }
    }

    // MARK: Remote input — touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, !isStartPageVisible, presentedViewController == nil else {
            super.touchesBegan(touches, with: event)
            return
        }
        isTouching = true
        lastTouchPoint = touch.location(in: view)
        lastTouchTimestamp = touch.timestamp
        scrollVelocity = .zero
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, isTouching, let last = lastTouchPoint else {
            super.touchesMoved(touches, with: event)
            return
        }
        let point = touch.location(in: view)
        let delta = CGPoint(x: point.x - last.x, y: point.y - last.y)
        let dt = max(touch.timestamp - lastTouchTimestamp, 1.0 / 240.0)
        lastTouchPoint = point
        lastTouchTimestamp = touch.timestamp
        lastMoveTime = CACurrentMediaTime()

        switch mode {
        case .cursor:
            let speed = hypot(delta.x, delta.y) / dt
            let acceleration = 1 + min(1.6, speed / 2600)
            let factor = settings.cursorSpeed * acceleration
            moveCursor(by: CGPoint(x: delta.x * factor, y: delta.y * factor))
        case .scroll:
            let factor = settings.scrollSpeed * 1.6
            let scrollDelta = CGPoint(x: delta.x * factor, y: delta.y * factor)
            scroll(by: scrollDelta, animated: false)
            let instant = CGPoint(x: scrollDelta.x / dt, y: scrollDelta.y / dt)
            scrollVelocity = CGPoint(x: scrollVelocity.x * 0.6 + instant.x * 0.4,
                                     y: scrollVelocity.y * 0.6 + instant.y * 0.4)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isTouching else { super.touchesEnded(touches, with: event); return }
        endTouch()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isTouching else { super.touchesCancelled(touches, with: event); return }
        endTouch()
    }

    private func endTouch() {
        isTouching = false
        lastTouchPoint = nil
        // A finger that stopped before lifting shouldn't fling the page.
        if CACurrentMediaTime() - lastMoveTime > 0.06 { scrollVelocity = .zero }
        let cap: CGFloat = 9000
        scrollVelocity = CGPoint(x: max(-cap, min(cap, scrollVelocity.x)), y: max(-cap, min(cap, scrollVelocity.y)))
    }

    private func moveCursor(by delta: CGPoint) {
        let bounds = view.bounds
        var point = cursor.hotspot
        point.x = max(bounds.minX + 4, min(bounds.maxX - 4, point.x + delta.x))
        point.y = max(bounds.minY + 4, min(bounds.maxY - 4, point.y + delta.y))
        cursor.hotspot = point
        hoverNeedsCheck = true
    }

    private func scroll(by delta: CGPoint, animated: Bool) {
        guard let scrollView = currentTab?.webView?.scrollView else { return }
        let inset = scrollView.adjustedContentInset
        let minX = -inset.left
        let minY = -inset.top
        let maxX = max(minX, scrollView.contentSize.width - scrollView.bounds.width + inset.right)
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
        let current = scrollView.contentOffset
        let target = CGPoint(x: max(minX, min(maxX, current.x + delta.x)),
                             y: max(minY, min(maxY, current.y + delta.y)))
        if target == current {
            if !animated { scrollVelocity = .zero }
            return
        }
        if animated {
            UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
                scrollView.contentOffset = target
            }
        } else {
            scrollView.contentOffset = target
        }
        hoverNeedsCheck = true
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard presentedViewController == nil, !isStartPageVisible else { return }
        let dt = max(link.targetTimestamp - link.timestamp, 1.0 / 120.0)

        // Inertial scrolling after a flick in Scroll mode.
        if mode == .scroll, !isTouching, hypot(scrollVelocity.x, scrollVelocity.y) > 12 {
            scroll(by: CGPoint(x: scrollVelocity.x * dt, y: scrollVelocity.y * dt), animated: false)
            let decay = pow(0.955, dt * 60)
            scrollVelocity = CGPoint(x: scrollVelocity.x * decay, y: scrollVelocity.y * decay)
        }

        // Edge scrolling: push the pointer against an edge to scroll that way.
        if mode == .cursor, isTouching, settings.edgeScrolling {
            let margin: CGFloat = 70
            let bounds = view.bounds
            let p = cursor.hotspot
            var delta = CGPoint.zero
            let maxSpeed: CGFloat = 1800 * settings.scrollSpeed
            if p.y < bounds.minY + margin { delta.y = -maxSpeed * (1 - (p.y - bounds.minY) / margin) * dt }
            if p.y > bounds.maxY - margin { delta.y = maxSpeed * (1 - (bounds.maxY - p.y) / margin) * dt }
            if p.x < bounds.minX + margin { delta.x = -maxSpeed * (1 - (p.x - bounds.minX) / margin) * dt }
            if p.x > bounds.maxX - margin { delta.x = maxSpeed * (1 - (bounds.maxX - p.x) / margin) * dt }
            if delta != .zero { scroll(by: delta, animated: false) }
        }

        // Adaptive pointer: check what's under the cursor at ~8 Hz.
        let now = link.timestamp
        if mode == .cursor, hoverNeedsCheck, now - lastHoverCheck > 0.12 {
            hoverNeedsCheck = false
            lastHoverCheck = now
            updateHover()
        }
    }

    // MARK: Page interaction

    /// Maps a screen point to CSS client coordinates. The engine lays the whole document out
    /// in its scroll view's content at `contentSize.width / documentWidth` points per CSS pixel,
    /// so convert into content space, unscale, then subtract the page's scroll position.
    private func cssPoint(for screenPoint: CGPoint, in webView: WBWebView) -> CGPoint {
        guard let scrollView = webView.scrollView else { return screenPoint }
        let content = view.convert(screenPoint, to: scrollView)
        let metrics = (webView.evaluate(PageScripts.layoutMetrics) ?? "").split(separator: ",").compactMap { Double($0) }
        guard metrics.count == 3 else { return content }
        let (documentWidth, scrollX, scrollY) = (metrics[0], metrics[1], metrics[2])
        let scale = documentWidth > 0 && scrollView.contentSize.width > 0 ? Double(scrollView.contentSize.width) / documentWidth : 1
        return CGPoint(x: Double(content.x) / scale - scrollX, y: Double(content.y) / scale - scrollY)
    }

    private func updateHover() {
        guard let webView = currentTab?.webView else { return }
        let point = cssPoint(for: cursor.hotspot, in: webView)
        cursor.isHoveringInteractive = webView.evaluate(PageScripts.hoverTest(x: Double(point.x), y: Double(point.y))) == "1"
    }

    private func performClick() {
        guard let tab = currentTab, let webView = tab.webView else { return }
        cursor.pulse()
        let point = cssPoint(for: cursor.hotspot, in: webView)
        guard let json = webView.evaluate(PageScripts.click(x: Double(point.x), y: Double(point.y))),
              let data = json.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = result["kind"] as? String else { return }

        switch kind {
        case "text":
            presentTextInput(value: result["value"] as? String ?? "",
                             label: result["label"] as? String ?? "",
                             inputType: result["inputType"] as? String ?? "text",
                             hasForm: result["hasForm"] as? Bool ?? false,
                             autocomplete: result["autocomplete"] as? String ?? "")
        case "login":
            presentLogin(username: result["username"] as? String,
                         isNewPassword: result["newPassword"] as? Bool ?? false)
        case "select":
            presentSelect(options: result["options"] as? [String] ?? [],
                          selected: result["selected"] as? Int ?? -1)
        default:
            hoverNeedsCheck = true
        }
    }

    private func presentTextInput(value: String, label: String, inputType: String, hasForm: Bool, autocomplete: String) {
        let title = label.isEmpty ? "Enter Text" : label.trimmingCharacters(in: .whitespacesAndNewlines)
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = value
            field.isSecureTextEntry = inputType == "password"
            switch inputType {
            case "email": field.keyboardType = .emailAddress
            case "url": field.keyboardType = .URL
            case "number", "tel": field.keyboardType = .numbersAndPunctuation
            default: field.keyboardType = .default
            }
            if ["email", "url", "password"].contains(inputType) {
                field.autocapitalizationType = .none
                field.autocorrectionType = .no
            }
            // Lets tvOS offer AutoFill from a nearby iPhone, e.g. the username step of a
            // two-page sign-in, or a code sent by text message.
            switch autocomplete {
            case "username", "email": field.textContentType = .username
            case "one-time-code": field.textContentType = .oneTimeCode
            default: break
            }
        }
        let submitTitle = inputType == "search" ? "Search" : "Go"
        alert.addAction(UIAlertAction(title: submitTitle, style: .default) { [weak self, weak alert] _ in
            let text = alert?.textFields?.first?.text ?? ""
            self?.currentTab?.evaluate(PageScripts.setFocusedValue(text, submit: true))
        })
        alert.addAction(UIAlertAction(title: "Done", style: .default) { [weak self, weak alert] _ in
            let text = alert?.textFields?.first?.text ?? ""
            self?.currentTab?.evaluate(PageScripts.setFocusedValue(text, submit: false))
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    /// One dialog for a whole sign-in form. Marking the fields as username and password
    /// makes tvOS offer AutoFill from the user's iPhone (or their Apple TV's saved passwords).
    private func presentLogin(username: String?, isNewPassword: Bool) {
        let host = URLResolver.displayHost(currentTab?.url)
        let title = host.isEmpty ? (isNewPassword ? "Create Account" : "Sign In") : (isNewPassword ? "Create Account on \(host)" : "Sign In to \(host)")
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        if let username {
            alert.addTextField { field in
                field.text = username
                field.placeholder = "Username or Email"
                field.textContentType = .username
                field.keyboardType = .emailAddress
                field.autocapitalizationType = .none
                field.autocorrectionType = .no
            }
        }
        alert.addTextField { field in
            field.placeholder = "Password"
            field.textContentType = isNewPassword ? .newPassword : .password
            field.isSecureTextEntry = true
        }
        func fill(submit: Bool) -> (UIAlertAction) -> Void {
            { [weak self, weak alert] _ in
                let fields = alert?.textFields ?? []
                let user = username == nil ? nil : fields.first?.text ?? ""
                let password = fields.last?.text ?? ""
                self?.currentTab?.evaluate(PageScripts.setLogin(username: user, password: password, submit: submit))
            }
        }
        alert.addAction(UIAlertAction(title: isNewPassword ? "Continue" : "Sign In", style: .default, handler: fill(submit: true)))
        alert.addAction(UIAlertAction(title: "Done", style: .default, handler: fill(submit: false)))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func presentSelect(options: [String], selected: Int) {
        guard !options.isEmpty else { return }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        for (index, option) in options.enumerated() {
            let title = index == selected ? "✓  \(option)" : option
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.currentTab?.evaluate(PageScripts.selectOption(index))
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }

    // MARK: Menu & panels

    private func presentMenu() {
        guard let tab = currentTab else { return }
        tab.captureSnapshot()
        let state = MenuState(
            title: tab.displayTitle,
            url: tab.url,
            canGoBack: tab.canGoBack,
            canGoForward: tab.canGoForward,
            isLoading: tab.isLoading,
            isBookmarked: library.isBookmarked(tab.url),
            isReaderActive: tab.isReaderActive,
            isStartPage: tab.isStartPage,
            blockedCount: tab.blockedCount,
            zoom: tab.zoom,
            mode: mode,
            userAgent: settings.userAgentMode,
            tabCount: tabManager.tabs.count,
            isPrivate: settings.privateBrowsing,
            canReopenTab: !tabManager.recentlyClosed.isEmpty,
            isDarkPages: settings.darkPages
        )
        let menu = BrowserMenuView(state: state,
                                   onAction: { [weak self] action in
                                       self?.dismiss(animated: true) { self?.run(action) }
                                   },
                                   onDismiss: { [weak self] in self?.dismiss(animated: true) })
        presentPanel(menu, animated: true)
    }

    private func presentPanel<Content: View>(_ content: Content, animated: Bool = true) {
        let host = UIHostingController(rootView: content)
        host.modalPresentationStyle = .overFullScreen
        host.modalTransitionStyle = .crossDissolve
        host.view.backgroundColor = .clear
        present(host, animated: animated)
    }

    private func presentSearch() {
        let search = AddressSearchView(
            library: library,
            settings: settings,
            onSubmit: { [weak self] text in
                self?.dismiss(animated: true) { self?.currentTab?.load(input: text) }
            },
            onOpen: { [weak self] url in
                self?.dismiss(animated: true) { self?.currentTab?.load(url) }
            },
            dismiss: { [weak self] in self?.dismiss(animated: true) }
        )
        presentPanel(search)
    }

    /// Opens a site from outside the browser (a Top Shelf favourite): in the current tab if it's
    /// showing the start page, otherwise in a new tab.
    func open(_ url: URL) {
        let load = { [weak self] in
            guard let self else { return }
            if let tab = self.currentTab, tab.isStartPage { tab.load(url) } else { self.tabManager.newTab(url: url, select: true) }
        }
        if presentedViewController != nil { dismiss(animated: false, completion: load) } else { load() }
    }

    func run(_ action: BrowserAction) {
        guard let tab = currentTab else { return }
        switch action {
        case .back: tab.goBack()
        case .forward: tab.goForward()
        case .reload: tab.reload()
        case .stop: tab.stop()
        case .home:
            if let home = settings.homePageURL { tab.load(home) } else { tab.showStartPage() }
        case .search:
            presentSearch()
        case .newTab:
            let newTab = tabManager.newTab(url: settings.homePageURL, select: true, after: tab)
            if newTab.url == nil { presentSearch() }
        case .closeTab:
            tabManager.close(tab)
        case .reopenTab:
            if tabManager.reopenClosedTab() == nil { toast.show("No recently closed tabs") }
        case .find:
            presentFind()
        case .toggleDarkPages:
            settings.darkPages.toggle()
            toast.show(settings.darkPages ? "Dark Pages On" : "Dark Pages Off")
        case .tabs:
            presentPanel(TabSwitcherView(
                tabManager: tabManager,
                onSelect: { [weak self] selected in
                    self?.tabManager.select(selected)
                    self?.dismiss(animated: true)
                },
                onNewTab: { [weak self] in
                    guard let self else { return }
                    self.tabManager.newTab(url: self.settings.homePageURL, select: true)
                    self.dismiss(animated: true)
                },
                onReopen: { [weak self] in
                    self?.tabManager.reopenClosedTab()
                    self?.dismiss(animated: true)
                },
                dismiss: { [weak self] in self?.dismiss(animated: true) }
            ))
        case .toggleBookmark:
            guard let url = tab.url else { return }
            let wasBookmarked = library.isBookmarked(url)
            library.toggleBookmark(title: tab.displayTitle, url: url)
            toast.show(wasBookmarked ? "Removed from Favorites" : "★ Added to Favorites")
        case .bookmarks:
            presentPanel(BookmarksView(
                library: library,
                onOpen: { [weak self] url in self?.dismiss(animated: true) { self?.currentTab?.load(url) } },
                dismiss: { [weak self] in self?.dismiss(animated: true) }
            ))
        case .history:
            presentPanel(HistoryView(
                library: library,
                onOpen: { [weak self] url in self?.dismiss(animated: true) { self?.currentTab?.load(url) } },
                dismiss: { [weak self] in self?.dismiss(animated: true) }
            ))
        case .settings:
            presentPanel(SettingsView(
                settings: settings,
                library: library,
                onClearData: { [weak self] in self?.tabManager.rebuildAllEngines(); self?.displaySelectedTab() },
                onShowControls: { [weak self] in
                    self?.dismiss(animated: true) {
                        self?.presentPanel(ControlsGuideView(dismiss: { [weak self] in self?.dismiss(animated: true) }))
                    }
                },
                dismiss: { [weak self] in self?.dismiss(animated: true) }
            ))
        case .reader:
            if !tab.toggleReader() { toast.show("Reader isn't available for this page") }
        case .playVideo:
            let videos = tab.playableVideoURLs()
            if let first = videos.first { playNatively(first) } else {
                toast.show("No playable video found on this page", duration: 2.4)
            }
        case .zoomIn:
            tab.applyZoom(tab.zoom + 0.15)
            toast.show("Zoom \(Int((tab.zoom * 100).rounded()))%")
        case .zoomOut:
            tab.applyZoom(tab.zoom - 0.15)
            toast.show("Zoom \(Int((tab.zoom * 100).rounded()))%")
        case .zoomReset:
            tab.applyZoom(1.0)
            toast.show("Zoom 100%")
        case .toggleMode:
            setMode(mode == .cursor ? .scroll : .cursor)
        case .toggleDesktop:
            settings.userAgentMode = settings.userAgentMode == .desktop ? .iPad : .desktop
        case .togglePrivate:
            settings.privateBrowsing.toggle()
            if settings.privateBrowsing { tabManager.saveSession() }
            toast.show(settings.privateBrowsing ? "Private Browsing On — nothing will be saved" : "Private Browsing Off")
        case .controls:
            presentPanel(ControlsGuideView(dismiss: { [weak self] in self?.dismiss(animated: true) }))
        case .nextTab:
            tabManager.selectNext(offset: 1)
        case .previousTab:
            tabManager.selectNext(offset: -1)
        }
    }

    private func presentFind() {
        presentPanel(FindBarView(
            onFind: { [weak self] query in Int(self?.currentTab?.evaluate(PageScripts.find(query)) ?? "") ?? 0 },
            onStep: { [weak self] delta in self?.currentTab?.evaluate(PageScripts.findStep(delta)) ?? "0/0" },
            dismiss: { [weak self] in
                self?.currentTab?.evaluate(PageScripts.findClear)
                self?.dismiss(animated: true)
            }
        ))
    }

    private func playNatively(_ url: URL) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        let player = AVPlayer(url: url)
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.delegate = self
        playerController = controller
        present(controller, animated: true) { player.play() }
    }

    private func presentEngineUnavailableAlert() {
        let alert = UIAlertController(
            title: "Web Engine Unavailable",
            message: "This version of tvOS doesn't include the WebKit engine Webby relies on. Please check for a Webby update.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Picture in Picture

extension BrowserViewController: AVPlayerViewControllerDelegate {
    func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(_ controller: AVPlayerViewController) -> Bool {
        true
    }

    func playerViewController(_ controller: AVPlayerViewController,
                              restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completion: @escaping (Bool) -> Void) {
        guard presentedViewController == nil else { completion(false); return }
        present(controller, animated: true) { completion(true) }
    }
}

// MARK: - BrowserTabDelegate

extension BrowserViewController: BrowserTabDelegate {
    func tab(_ tab: BrowserTab, requestsNewTabWith url: URL) {
        tabManager.newTab(url: url, select: true, after: tab)
        toast.show("Opened in New Tab")
    }

    func tabDidUpdate(_ tab: BrowserTab) {
        guard tab === currentTab else { return }
        // The page under the pointer may have changed, so refresh its hover state.
        hoverNeedsCheck = true
        syncContent()
    }
}
