//
//  BrowserTab.swift
//  Webby
//

import UIKit
import Combine

protocol BrowserTabDelegate: AnyObject {
    func tab(_ tab: BrowserTab, requestsNewTabWith url: URL)
    func tabDidUpdate(_ tab: BrowserTab)
}

final class BrowserTab: NSObject, ObservableObject, Identifiable, WBWebViewDelegate {

    let id: UUID
    @Published private(set) var title: String = ""
    @Published private(set) var url: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var blockedCount = 0
    @Published private(set) var isReaderActive = false
    @Published private(set) var lastError: String?
    @Published var snapshot: UIImage?

    /// Page zoom applied with CSS after every load.
    var zoom: Double

    weak var delegate: BrowserTabDelegate?

    private(set) var webView: WBWebView?
    private var activeLoads = 0
    private var progressTimer: Timer?
    private var pendingURL: URL?
    private var readerSourceURL: URL?
    private var blockObserver: NSObjectProtocol?

    private let settings = BrowserSettings.shared
    private let library = LibraryStore.shared

    init(id: UUID = UUID(), url: URL? = nil, title: String = "") {
        self.id = id
        self.zoom = BrowserSettings.shared.defaultZoom
        super.init()
        self.url = url
        self.title = title
        self.pendingURL = url
        blockObserver = NotificationCenter.default.addObserver(forName: .contentBlockerDidBlock, object: nil,
                                                               queue: .main) { [weak self] note in
            guard let self, self.webView != nil else { return }
            let page = note.userInfo?["page"] as? URL
            if page == nil || page?.host == self.url?.host { self.blockedCount += 1 }
        }
    }

    deinit {
        progressTimer?.invalidate()
        if let blockObserver { NotificationCenter.default.removeObserver(blockObserver) }
    }

    var isStartPage: Bool { url == nil && pendingURL == nil && !isLoading }

    var displayTitle: String {
        if !title.isEmpty { return title }
        if let url { return URLResolver.displayHost(url) }
        return "Start Page"
    }

    // MARK: Web view lifecycle

    /// Creates the engine view on demand so background tabs cost nothing until shown.
    @discardableResult
    func makeWebViewIfNeeded() -> WBWebView {
        if let webView { return webView }
        let view = WBWebView(frame: UIScreen.main.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.delegate = self
        webView = view
        if let pendingURL {
            self.pendingURL = nil
            view.load(URLRequest(url: pendingURL))
        }
        return view
    }

    /// Recreates the engine (used after a user-agent change) and reloads the current page.
    func rebuildWebView() {
        let current = url
        webView?.stopLoading()
        webView?.delegate = nil
        webView?.removeFromSuperview()
        webView = nil
        pendingURL = current
        activeLoads = 0
        finishProgress()
    }

    /// Releases the engine to free memory (tab stays restorable).
    func suspend() {
        guard let webView, !webView.isLoading else { return }
        snapshot = webView.snapshot(withMaxWidth: 640) ?? snapshot
        rebuildWebView()
    }

    // MARK: Navigation

    func load(_ url: URL) {
        lastError = nil
        isReaderActive = false
        self.url = url
        if let webView {
            webView.load(URLRequest(url: url))
        } else {
            pendingURL = url
        }
        delegate?.tabDidUpdate(self)
    }

    func load(input: String) {
        load(URLResolver.url(from: input, engine: settings.searchEngine))
    }

    func goBack() {
        if isReaderActive, let source = readerSourceURL { load(source); return }
        webView?.goBack()
    }

    func goForward() { webView?.goForward() }

    func reload() {
        if isReaderActive, let source = readerSourceURL { load(source); return }
        if webView?.currentURL == nil, let url { load(url) } else { webView?.reload() }
    }

    func stop() {
        webView?.stopLoading()
        activeLoads = 0
        finishProgress()
    }

    /// Shows the native start page. The engine keeps its page underneath so Menu can return to it.
    func showStartPage() {
        captureSnapshot()
        webView?.stopLoading()
        activeLoads = 0
        finishProgress()
        url = nil
        title = ""
        pendingURL = nil
        isReaderActive = false
        delegate?.tabDidUpdate(self)
    }

    /// Returns from the start page to whatever the engine was last showing.
    func resumeFromStartPage() -> Bool {
        guard url == nil, let current = webView?.currentURL,
              let scheme = current.scheme, scheme == "http" || scheme == "https" else { return false }
        url = current
        refreshState()
        return true
    }

    @discardableResult
    func evaluate(_ script: String) -> String? {
        webView?.evaluate(script)
    }

    func captureSnapshot() {
        guard let webView, url != nil else { return }
        snapshot = webView.snapshot(withMaxWidth: 640)
    }

    // MARK: Features

    func applyZoom(_ value: Double) {
        zoom = min(3.0, max(0.5, value))
        evaluate(PageScripts.setZoom(zoom))
        settings.setZoom(zoom, for: url)
    }

    /// Turns Dark Pages on or off for this page. The engine's own background (seen around the
    /// page, e.g. in the overscan area) follows, so a darkened page has no white edges.
    func applyDarkPages(_ on: Bool) {
        guard let webView, !isReaderActive else { return }
        let darkened = webView.evaluate(PageScripts.darkPages(on)) == "1"
        let color: UIColor = darkened ? .black : .white
        webView.scrollView?.backgroundColor = color
        webView.subviews.forEach { $0.backgroundColor = color }
    }

    func toggleReader() -> Bool {
        if isReaderActive, let source = readerSourceURL {
            load(source)
            return true
        }
        guard let json = evaluate(PageScripts.extractArticle), !json.isEmpty,
              let data = json.data(using: .utf8),
              let article = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = article["html"] as? String else { return false }
        let html = PageScripts.readerDocument(title: article["title"] as? String ?? title,
                                              byline: article["byline"] as? String ?? "",
                                              site: article["site"] as? String ?? "",
                                              body: body)
        readerSourceURL = url
        webView?.loadHTML(html, baseURL: url)
        isReaderActive = true
        return true
    }

    func playableVideoURLs() -> [URL] {
        guard let json = evaluate(PageScripts.findVideos),
              let data = json.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return list.compactMap(URL.init(string:))
    }

    // MARK: Progress

    private func beginProgress() {
        if !isLoading {
            isLoading = true
            progress = 0.08
        }
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Ease toward 90% while the engine works; jump to 100% on finish.
            self.progress += (0.9 - self.progress) * 0.06
        }
    }

    private func finishProgress() {
        progressTimer?.invalidate()
        progressTimer = nil
        guard isLoading else { return }
        progress = 1
        isLoading = false
    }

    private func refreshState() {
        guard let webView else { return }
        canGoBack = webView.canGoBack || isReaderActive
        canGoForward = webView.canGoForward
        if !isReaderActive,
           let json = webView.evaluate(PageScripts.pageInfo), let data = json.data(using: .utf8),
           let info = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            if let href = info["href"], let parsed = URL(string: href),
               let scheme = parsed.scheme, scheme == "http" || scheme == "https" {
                url = parsed
            }
            title = info["title"] ?? title
        } else if isReaderActive {
            title = webView.evaluate("document.title") ?? title
        }
        delegate?.tabDidUpdate(self)
    }

    // MARK: WBWebViewDelegate

    func webView(_ webView: WBWebView, shouldStartLoad request: URLRequest, navigationType: WBNavigationType) -> Bool {
        guard let target = request.url else { return true }
        if target.scheme == PageScripts.bridgeScheme {
            handleBridge(target)
            return false
        }
        if let scheme = target.scheme?.lowercased(), !["http", "https", "about", "data", "blob", "file"].contains(scheme) {
            // tel:, mailto:, itms-apps:, etc. can't be handled on Apple TV.
            return false
        }
        let isMainFrame = request.mainDocumentURL == nil || request.mainDocumentURL == target
        if isMainFrame, let scheme = target.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            if navigationType == .linkClicked || navigationType == .formSubmitted { isReaderActive = false }
            if !isReaderActive {
                if url?.host != target.host { blockedCount = 0 }
                url = target
            }
        }
        return true
    }

    func webViewDidStartLoad(_ webView: WBWebView) {
        activeLoads += 1
        lastError = nil
        beginProgress()
        delegate?.tabDidUpdate(self)
    }

    func webViewDidFinishLoad(_ webView: WBWebView) {
        activeLoads = max(0, activeLoads - 1)
        webView.evaluate(PageScripts.bootstrap)
        refreshState()
        zoom = settings.zoom(for: url)
        if abs(zoom - 1.0) > 0.01 { webView.evaluate(PageScripts.setZoom(zoom)) }
        if settings.darkPages { applyDarkPages(true) }
        if activeLoads == 0 && !webView.isLoading {
            finishProgress()
            if !settings.privateBrowsing, !isReaderActive, let url {
                library.recordVisit(title: title, url: url)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.captureSnapshot() }
        }
    }

    func webView(_ webView: WBWebView, didFailLoad error: Error) {
        activeLoads = max(0, activeLoads - 1)
        let nsError = error as NSError
        if activeLoads == 0 { finishProgress() }
        refreshState()
        // Cancellations happen constantly (redirects, blocked trackers, user stops).
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled),
              nsError.code != 102 /* WebKit "frame load interrupted" */ else { return }
        lastError = nsError.localizedDescription
        delegate?.tabDidUpdate(self)
    }

    private func handleBridge(_ url: URL) {
        let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "v" })?.value ?? ""
        switch url.host {
        case "open":
            guard let target = URL(string: value) else { return }
            if settings.openPopupsInNewTab {
                delegate?.tab(self, requestsNewTabWith: target)
            } else {
                load(target)
            }
        default:
            break
        }
    }
}
