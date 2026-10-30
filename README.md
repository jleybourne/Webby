<p align="center"><img src="docs/icon.png" width="400" alt="Webby icon"></p>

# Webby

**A fast, native web browser for Apple TV, built on Safari's WebKit engine.**

Webby drives the WebKit engine that ships inside tvOS directly from the Siri Remote. It has a smooth adaptive pointer, inertial scrolling, tabs, favorites and network-level ad blocking, and its 10-foot interface is built with SwiftUI.

This README is also the developer guide: it explains how the app actually works, file by file, so you can find your way around the code.

## Contents

1. [At a glance](#at-a-glance)
2. [How Webby renders web pages](#how-webby-renders-web-pages-the-important-part)
3. [Features](#features)
4. [Siri Remote controls](#siri-remote-controls)
5. [Architecture](#architecture)
6. [From typing a URL to a page on screen](#from-typing-a-url-to-a-page-on-screen)
7. [Remote input, pointer and focus](#remote-input-pointer-and-focus)
8. [Features in detail](#features-in-detail)
9. [Persistence](#persistence)
10. [External services, network and permissions](#external-services-network-and-permissions)
11. [Building, running, testing and releasing](#building-running-testing-and-releasing)
12. [Gotchas, known issues and loose ends](#gotchas-known-issues-and-loose-ends)
13. [Contributing and licence](#contributing)

---

## At a glance

| | |
|---|---|
| **What** | A full web browser for Apple TV, controlled with the Siri Remote |
| **Platform** | tvOS only (`TARGETED_DEVICE_FAMILY: "3"`), arm64 Apple TVs |
| **Minimum OS** | tvOS 17.0 (`project.yml` → `deploymentTarget.tvOS`) |
| **Languages** | Swift 5 (UIKit + SwiftUI + Combine), plus one Objective-C wrapper class |
| **Project generation** | [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`. `Webby.xcodeproj` is generated and git-ignored |
| **Bundle IDs** | `app.webby` (app), `app.webby.topshelf` (extension), app group `group.app.webby` |
| **Version** | `MARKETING_VERSION` 1.0.0. `CURRENT_PROJECT_VERSION` is 1 locally; `scripts/testflight.sh` overrides it with the next build number from App Store Connect |
| **Dependencies** | None. No Swift packages, no CocoaPods |
| **Pricing** | No free/paid split. Every feature is available and there is no StoreKit code. MIT licensed |
| **App Store** | Not viable as built (private API). See [App Store viability](#app-store-viability) |

### Targets

| Target | Type | Sources | Purpose |
|---|---|---|---|
| `Webby` | tvOS application | `Webby/`, `Shared/` | The browser. Depends on and embeds `WebbyTopShelf` |
| `WebbyTopShelf` | tvOS app extension (`com.apple.tv-top-shelf`) | `TopShelf/`, `Shared/` | Shows your favourite sites on the Home Screen Top Shelf |

There is one scheme, `Webby` (Debug for run, Release for archive). There is **no test target**; the scheme's `Testables` list is empty.

---

## How Webby renders web pages (the important part)

tvOS has **no public web view**. `WKWebView` and `SFSafariViewController` don't exist on tvOS, and `UIWebView` is marked unavailable in the tvOS SDK headers. However, the `UIWebView` **class itself still ships in tvOS's UIKit at runtime**, backed by the legacy (WebKit1) engine. Webby uses that class.

### The wrapper: `Webby/Engine/WBWebView.{h,m}`

`WBWebView` is a plain `UIView` subclass written in Objective-C that hides the private class from the rest of the app:

1. **Runtime lookup.** `NSClassFromString(@"UIWebView")` finds the class. Nothing links against it at compile time, so the SDK's "unavailable" marking never applies.
2. **A private protocol.** `WBLegacyWebViewSurface` (declared inside `WBWebView.m`) redeclares just the `UIWebView` methods Webby needs (`loadRequest:`, `loadHTMLString:baseURL:`, `goBack`, `stringByEvaluatingJavaScriptFromString:`, `scrollView`, `request`, and so on). The engine instance is cast to `UIView<WBLegacyWebViewSurface>` so calls compile.
3. **Defensive calls.** Every property access is guarded with `respondsToSelector:`, so if Apple changes the class Webby degrades instead of crashing.
4. **Engine setup** (`setUpEngine`): `scalesPageToFit = YES`, inline media playback on, autoplay allowed (`mediaPlaybackRequiresUserAction = NO`), `keyboardDisplayRequiresUserAction = NO`, and crucially **`userInteractionEnabled = NO`**. The engine never receives touches or focus; Webby drives it entirely from outside.
5. **Delegate forwarding.** `WBWebView` sets itself as the engine's delegate and forwards the four `UIWebViewDelegate` callbacks (`shouldStartLoadWithRequest`, `didStartLoad`, `didFinishLoad`, `didFailLoadWithError`) to a clean Swift-friendly `WBWebViewDelegate` protocol.
6. **Availability check.** `WBWebView.isEngineAvailable` returns whether the class exists. `BrowserViewController.viewDidAppear` shows a "Web Engine Unavailable" alert if it doesn't, rather than crashing.
7. **Snapshots.** `snapshotWithMaxWidth:` renders the view's layer into a `UIImage` for tab thumbnails.

Swift sees the wrapper through `Webby/Engine/Webby-Bridging-Header.h` (set as `SWIFT_OBJC_BRIDGING_HEADER` in `project.yml`).

### What that engine can and can't do

The legacy engine shapes the whole app's design:

| Constraint | Consequence in Webby |
|---|---|
| JavaScript can only be run **synchronously**, returning a **string** (`stringByEvaluatingJavaScriptFromString:`) | Every script in `Webby/Browser/PageScripts.swift` returns a string, usually JSON, which Swift parses with `JSONSerialization` |
| No script message handlers (no `WKScriptMessageHandler`) | Page → app messages use a **URL bridge**: the injected script loads `webby://<command>?v=<value>` in a hidden iframe, and `BrowserTab.webView(_:shouldStartLoad:navigationType:)` intercepts it and returns `false` |
| No user scripts injected at document start | `PageScripts.bootstrap` is evaluated after **every** `webViewDidFinishLoad` (guarded by `window.__webbyInstalled`) |
| No `WKContentRuleList` | Ad blocking is a global `URLProtocol` subclass (`ContentBlocker`), which the legacy engine honours for its network requests |
| User agent can't be set per view | The engine reads the `UserAgent` key from the `UserDefaults` **registration domain** when a view is created. Changing UA means re-registering and rebuilding every engine (`BrowserSettings.applyUserAgent`, `TabManager.rebuildAllEngines`) |
| No progress API | `BrowserTab` fakes a progress bar: it eases toward 90% on a 0.1 s timer and jumps to 100% when loads finish |
| The engine has no input on tvOS | Pointer, clicks, typing and scrolling are all synthesised by Webby (see [Remote input](#remote-input-pointer-and-focus)) |

### App Store viability

**Not viable as built.** Instantiating `UIWebView` on tvOS is private API use (App Review Guideline 2.5.1: only public APIs). Apple also stopped accepting apps that reference `UIWebView` on iOS years ago, and `scripts/testflight.sh` says so plainly: *"App Store Connect may reject the build during processing."* Personal installs from Xcode, `scripts/install-appletv.sh`, and possibly TestFlight (check with `python3 scripts/asc.py builds`) are the realistic distribution routes. Two other things reviewers would query: `NSAllowsArbitraryLoads` in `Info.plist`, and the `audio` background mode.

If a future tvOS removes the class, the app shows the "Web Engine Unavailable" alert, and the Settings → About "Engine" row reads "Unavailable".

---

## Features

| | |
|---|---|
| 🖱️ **Adaptive pointer** | iPadOS-style cursor that grows and tints over links and buttons. Movement speeds up the faster you swipe. |
| 📜 **Scroll mode** | Hold Click to switch. Swipe to scroll with momentum, like a trackpad. |
| ↕️ **Edge and D-pad scrolling** | Push the pointer against a screen edge, or click the D-pad edges, to page around. |
| ⌨️ **Real form input** | Clicking a text field opens the tvOS keyboard (with dictation), or type on your iPhone. Dropdowns become native pickers. Choose *Go* to submit forms. |
| 🔑 **Sign-in with AutoFill** | Sign-in forms open as one Username and Password dialog that tvOS can AutoFill from your iPhone. |
| 🗂️ **Tabs** | Visual tab switcher with live thumbnails. Pop-ups and `target=_blank` links open in new tabs. Tabs are restored on launch, closed tabs can be reopened, and idle tabs are suspended automatically to save memory. |
| ⭐ **Favorites and bookmarks** | One-click favoriting, a favorites grid on the start page, and a "Frequently Visited" row. Bookmarks sync between Apple TVs through iCloud. |
| 📺 **Top Shelf** | With Webby in the top row of the Home Screen, your favorite sites appear above it. Select one to open it. |
| 👥 **A profile for each person** | Everyone in the household gets their own bookmarks, history, tabs and settings, following the Apple TV's current user. |
| 🕘 **History** | Grouped by day. You can search it from the address bar. |
| 🔎 **Smart address bar** | tvOS search keyboard with live suggestions, plus your bookmarks and history. Choose Google, DuckDuckGo, Bing, Brave or Ecosia for searches. |
| 🛡️ **Ad and tracker blocking** | About 170 ad and tracker networks (174 domains) are blocked before any request leaves the device. A live counter shows what was blocked on each page. |
| 📖 **Reader mode** | Strips articles down to large, TV-legible text. |
| 🔦 **Find on Page** | Highlights every match and steps through them. |
| 🌙 **Dark Pages** | Turns bright pages dark, leaving photos and video as they are. |
| ▶️ **Native video** | Sends a page's video to the system AVPlayer for full Siri Remote scrubbing, with Picture in Picture. |
| 🔍 **Page zoom** | Zoom from 50% to 300%. Webby remembers the zoom for each site, and you can set a default. |
| 🖥️ **Desktop / mobile sites** | Switch user agent: Mac Safari, iPad, iPhone or Apple TV. |
| 🕶️ **Private browsing** | No history and no saved tabs. Website data is wiped when you leave the app. |
| ⚡ **Built for speed** | Native start page that appears instantly, a 256 MB shared HTTP cache, lazily created engines, and LRU suspension of background tabs. |

---

## Siri Remote controls

| Input | Action |
|---|---|
| Swipe | Move pointer / scroll (Scroll mode) |
| Click | Click under pointer (in Scroll mode, a click returns to Cursor mode) |
| Click & hold (0.55 s) | Toggle Cursor ↔ Scroll mode |
| Play/Pause | Open the Webby menu (address bar, tabs, favorites, tools) |
| Back / Menu | Leave Scroll mode → go back → close the tab if it has no history and other tabs exist → show the start page |
| D-pad edges | Up/down: 60% of a screen. Left/right: 50%. Page Up/Down keys: 90% |

On the start page, panels and menus, the normal tvOS focus engine takes over (see [Focus](#focus-how-native-ui-and-the-page-coexist)).

---

## Architecture

### Folder map

| Path | Purpose |
|---|---|
| `project.yml` | XcodeGen spec: targets, deployment target, bundle IDs, entitlements, team, scheme |
| `Webby/App/AppDelegate.swift` | `@main` entry point. Sets up the cache, cookie policy, content blocker, user agent, iCloud sync, Top Shelf publisher and the window. Handles `webbytv://` deep links |
| `Webby/Engine/WBWebView.h`, `WBWebView.m` | Objective-C wrapper around the runtime `UIWebView` class |
| `Webby/Engine/Webby-Bridging-Header.h` | Exposes `WBWebView` to Swift |
| `Webby/Engine/ContentBlocker.swift` | `URLProtocol` that fails requests to blocked ad/tracker hosts, and the block list |
| `Webby/Browser/BrowserViewController.swift` | The root controller: hosts the active engine, remote input, pointer, scrolling, menus, panels, dialogs, video |
| `Webby/Browser/BrowserTab.swift` | One tab: owns its `WBWebView`, navigation state, progress, reader/zoom/dark/video helpers, bridge handling |
| `Webby/Browser/TabManager.swift` | The tab list, selection, session save/restore, recently closed, engine LRU suspension |
| `Webby/Browser/PageScripts.swift` | Every piece of JavaScript Webby injects, plus the reader-mode HTML template |
| `Webby/Browser/CursorView.swift` | `CursorView` (pointer), `StatusHUDView` (top status capsule), `ToastView` (transient messages) |
| `Webby/Store/BrowserSettings.swift` | All settings (`UserDefaults`), `SearchEngine`, `UserAgentMode`, `URLResolver` |
| `Webby/Store/LibraryStore.swift` | Bookmarks and history (`UserDefaults` JSON) and iCloud key-value sync of bookmarks |
| `Webby/Store/TopShelfPublisher.swift` | Renders favourite tiles into the app group and tells tvOS the Top Shelf changed |
| `Webby/UI/BrowserMenuView.swift` | The Play/Pause menu, `BrowserAction` enum and `MenuState` |
| `Webby/UI/StartPageView.swift` | Native SwiftUI start page |
| `Webby/UI/AddressSearchView.swift` | Address bar / search screen and `SuggestionService` |
| `Webby/UI/FindBarView.swift` | Find on Page bar |
| `Webby/UI/LibraryViews.swift` | Tab switcher, bookmarks grid, history list |
| `Webby/UI/SettingsView.swift` | Settings form, controls guide, `DataCleaner` |
| `Webby/UI/Components.swift` | `Theme`, `FaviconView`, `SiteTile`, `ChromeButton`, `PanelContainer`, `OverlayBackdrop`, etc. |
| `Webby/Resources/` | `Info.plist`, `Webby.entitlements`, asset catalog (layered app icon, Top Shelf images) |
| `Shared/ShelfFavorites.swift` | Codable Top Shelf data, app group storage and the `webbytv://open?url=` deep-link format. Compiled into both targets |
| `TopShelf/ContentProvider.swift` | `TVTopShelfContentProvider` that builds the "Favorites" shelf |
| `TopShelf/Info.plist`, `WebbyTopShelf.entitlements` | Extension config |
| `scripts/install-appletv.sh` | Build, sign and install on a paired Apple TV |
| `scripts/testflight.sh` | Archive and upload to TestFlight |
| `scripts/asc.py` | App Store Connect API helper (next build number, build status) |
| `scripts/icon/` | Icon generator: `gen.py` (SVG), `render.js` (Playwright PNG render), `build.sh` (all sizes) |
| `docs/icon.png` | Icon used at the top of this README |

### Key types and how they connect

```
AppDelegate
 └─ UIWindow.rootViewController = BrowserViewController
      ├─ tabManager: TabManager ──── tabs: [BrowserTab] ──── webView: WBWebView? ──── UIWebView (runtime)
      │                               (delegate = BrowserViewController)   (delegate = BrowserTab)
      ├─ BrowserSettings.shared  (singleton, @Published settings)
      ├─ LibraryStore.shared     (singleton, bookmarks/history, iCloud)
      ├─ view hierarchy: webContainer → surface (RemoteSurfaceView) → progressBar, hud, toast, cursor
      ├─ startPageHost: UIHostingController<StartPageView>  (shown when the tab has no URL)
      └─ presents SwiftUI panels via UIHostingController (.overFullScreen):
           BrowserMenuView, AddressSearchView, TabSwitcherView, BookmarksView,
           HistoryView, SettingsView, FindBarView, ControlsGuideView, AVPlayerViewController

TopShelfPublisher.shared ── observes LibraryStore.$bookmarks ── writes ShelfFavorites to group.app.webby
TopShelf ContentProvider ── reads ShelfFavorites ── items open webbytv://open?url=… ── AppDelegate.open(url:)
ContentBlocker (URLProtocol, registered globally) ── posts .contentBlockerDidBlock ── BrowserTab.blockedCount
```

| Type | File | Role |
|---|---|---|
| `BrowserViewController` | `Webby/Browser/BrowserViewController.swift` | Owns `TabManager`; implements `BrowserTabDelegate` and `AVPlayerViewControllerDelegate`; `run(_ action: BrowserAction)` is the single dispatcher for every menu/start-page action |
| `BrowserTab` | `Webby/Browser/BrowserTab.swift` | `ObservableObject` with `@Published` `title`, `url`, `isLoading`, `progress`, `canGoBack/Forward`, `blockedCount`, `isReaderActive`, `lastError`, `snapshot`. Implements `WBWebViewDelegate` |
| `TabManager` | `Webby/Browser/TabManager.swift` | `@Published tabs`, `selectedID`, `recentlyClosed`. Limits: `maxLiveEngines = 4`, `maxTabs = 24`, 10 recently closed |
| `WBWebView` | `Webby/Engine/WBWebView.m` | Engine wrapper (see above) |
| `PageScripts` | `Webby/Browser/PageScripts.swift` | Static JS strings/builders; `jsString` safely encodes Swift strings as JS literals via JSON |
| `BrowserSettings` | `Webby/Store/BrowserSettings.swift` | Settings singleton; every `@Published` property writes through to `UserDefaults` in `didSet` |
| `URLResolver` | `Webby/Store/BrowserSettings.swift` | Turns typed text into a URL or search; `displayHost` strips `www.` |
| `LibraryStore` | `Webby/Store/LibraryStore.swift` | Bookmarks, history, top sites, address-bar matches, iCloud sync |
| `BrowserAction` / `MenuState` | `Webby/UI/BrowserMenuView.swift` | Action enum shared by menu, start page and controller; snapshot of state passed into the menu |
| `ContentBlocker` | `Webby/Engine/ContentBlocker.swift` | Thread-safe `isEnabled` flag (NSLock), `shouldBlock(host:)`, `blockedDomains` |
| `ShelfFavorites` | `Shared/ShelfFavorites.swift` | Shared app/extension model and deep-link helpers |

State flows one way: `BrowserTab` publishes changes → `BrowserViewController.syncContent()` (subscribed to the selected tab's `objectWillChange`, and called from `tabDidUpdate`) reconciles the screen: engine vs start page, progress bar, HUD and error toast.

---

## From typing a URL to a page on screen

### Launch

`AppDelegate.application(_:didFinishLaunchingWithOptions:)`:

1. `URLCache.shared` = 64 MB memory / 256 MB disk (`"WebbyCache"`).
2. `HTTPCookieStorage.shared.cookieAcceptPolicy = .onlyFromMainDocumentDomain` (no third-party cookies).
3. `ContentBlocker.install(enabled:)` registers the `URLProtocol`.
4. `settings.applyUserAgent()` registers the UA before any engine exists.
5. `LibraryStore.shared.startCloudSync()` and `TopShelfPublisher.shared.start(library:)`.
6. Window with `BrowserViewController` as root. Its `viewDidLoad` builds the layers, wires gestures and Combine subscriptions, calls `tabManager.restoreSession()`, and starts a `CADisplayLink` (`tick`).
7. `viewDidAppear`: engine-unavailable alert, or the Controls guide on first run (`settings.showHints`).

### Entering a URL

1. **Play/Pause** → `handlePlayPause` → `presentMenu()`. The menu's focused address bar button (or the start page's search button) sends `.search` → `presentSearch()`.
2. `AddressSearchView` shows a `.searchable` field (tvOS search keyboard with dictation). As you type, `.task(id: text)` waits 220 ms then calls `SuggestionService.suggestions(for:)`; local matches come from `LibraryStore.matches(for:)`.
3. Submitting calls `onSubmit(text)` → controller dismisses → `currentTab.load(input:)`.
4. `BrowserTab.load(input:)` → `URLResolver.url(from:engine:)`:
   - Already a URL with `http`, `https`, `about`, `data` or `file` scheme → used as-is.
   - No spaces and looks like a host (`a.b` with an alphabetic TLD of 2+ letters, `localhost`, or an IPv4 address) → `https://` prefix (`http://` for localhost/IP).
   - Otherwise → search URL for the chosen `SearchEngine`.
5. `BrowserTab.load(_ url:)` sets `url`, clears errors and reader state, and either calls `webView.load(URLRequest)` or, if no engine exists yet, stores `pendingURL`. Then `delegate?.tabDidUpdate`.

### Displaying

6. `BrowserViewController.syncContent()` sees a non-start-page tab and calls `tab.makeWebViewIfNeeded()`. This **creates the engine lazily** (and loads `pendingURL`), adds it to `webContainer`, and fades out the start page host.
7. The engine calls back through `WBWebView` into `BrowserTab`:
   - `shouldStartLoad`: intercepts the `webby://` bridge; refuses non-web schemes (`tel:`, `mailto:`, `itms-apps:`…); for main-frame `http(s)` navigations updates `url` and resets `blockedCount` when the host changes.
   - `webViewDidStartLoad`: `activeLoads += 1`, `beginProgress()`.
   - `webViewDidFinishLoad`: evaluates `PageScripts.bootstrap`, `refreshState()` (reads `title` and `location.href` via `PageScripts.pageInfo`), reapplies per-site zoom and Dark Pages; when `activeLoads` hits 0, finishes progress, records history (unless private or reader), and captures a snapshot 0.4 s later.
   - `didFailLoad`: ignores cancellations (`NSURLErrorCancelled`, which includes blocked requests) and WebKit error 102 ("frame load interrupted"); otherwise sets `lastError`, shown as a toast.
8. Meanwhile `ContentBlocker.canInit(with:)` runs for each request; blocked ones fail immediately and post `.contentBlockerDidBlock`, which increments `blockedCount` on tabs whose host matches.
9. The HUD (`StatusHUDView`) flashes the lock/globe icon, host, spinner, blocked count and input mode, staying visible while loading.

### Start page vs page

A tab is on the start page when `url == nil && pendingURL == nil && !isLoading` (`BrowserTab.isStartPage`). `showStartPage()` clears `url` but **leaves the engine's page underneath**, so pressing Menu on the start page calls `resumeFromStartPage()` and returns to it.

---

## Remote input, pointer and focus

### View layers (`BrowserViewController.viewDidLoad`)

From back to front: `webContainer` (the active `WBWebView`) → `surface` (`RemoteSurfaceView`, transparent, `canBecomeFocused = true`) → start page host (when visible) → `progressBar` → `hud` → `toast` → `cursor`.

### Touches (swipes)

`touchesBegan/Moved/Ended` on the controller read the Siri Remote touch surface:

- **Cursor mode:** `moveCursor(by:)` with acceleration `1 + min(1.6, speed / 2600)` times `settings.cursorSpeed`; the pointer is clamped 4 pt inside the screen.
- **Scroll mode:** `scroll(by:animated:)` moves the engine's `scrollView.contentOffset` directly (factor `scrollSpeed × 1.6`), and keeps a smoothed velocity. On lift, velocity is zeroed if the finger had stopped for over 60 ms, and capped at 9000 pt/s.

### Display link (`tick`)

Runs every frame while no panel is presented and the start page is hidden:

- **Inertia:** in Scroll mode, keeps scrolling with velocity decaying by `0.955` per 60 Hz frame until below 12 pt/s.
- **Edge scrolling:** in Cursor mode, while touching, within 70 pt of an edge, scrolls up to `1800 × scrollSpeed` pt/s (if `settings.edgeScrolling`).
- **Hover:** at most every 0.12 s (about 8 Hz), `updateHover()` runs `PageScripts.hoverTest` at the pointer. It returns `"1"` for links, buttons, inputs, ARIA roles, `[tabindex]` or `cursor: pointer`, and `CursorView.isHoveringInteractive` grows and tints the pointer.

### Screen → page coordinates

`cssPoint(for:in:)` converts the pointer's screen position into the scroll view's content coordinates, then divides by the engine's scale (`contentSize.width / document.documentElement.scrollWidth`, from `PageScripts.layoutMetrics`) and subtracts `window.scrollX/Y`. That gives CSS client coordinates for `document.elementFromPoint`.

### Clicks

`selectTap` (Select press, which must fail `selectHold` first) → `performClick()` → `PageScripts.click(x:y:)`. The script finds the element under the point and returns JSON:

| `kind` | When | Native response |
|---|---|---|
| `select` | A `<select>` | `presentSelect`: action sheet of options → `PageScripts.selectOption` |
| `login` | A text/password input in a form with **exactly one** visible password field (the clicked field is that password or the text field before it) | `presentLogin`: one alert with username (`.username`) and password (`.password` or `.newPassword`) fields so tvOS offers AutoFill → `PageScripts.setLogin` |
| `text` | Other text inputs, textareas, contenteditable | `presentTextInput`: alert with a keyboard type and `textContentType` from the input's `type`/`autocomplete` → `PageScripts.setFocusedValue` |
| `click` / `toggle` | Anything else | The script already dispatched `pointerover/down`, `mouseover/down`, `focus`, `pointerup`, `mouseup` then `element.click()` |

Writing values uses the native `value` property setter and fires `input` and `change` events so React/Vue-style frameworks notice. **Go/Sign In** additionally dispatches Enter `keydown/keypress/keyup` and, if not prevented, `form.requestSubmit()` (or `submit()`); **Done** fills without submitting.

### Presses

`pressesBegan` → `handlePress(_:)` handles Menu and arrow/page presses and records consumed presses so `pressesEnded` doesn't pass them to UIKit (which would exit the app on Menu). Play/Pause is a separate `UITapGestureRecognizer` on the root view.

### Focus: how native UI and the page coexist

- `preferredFocusEnvironments` returns the start page host's view when it's visible, otherwise the invisible `surface`. Keeping focus on `surface` is what lets raw touches and presses reach the controller while a page is shown.
- When the start page is visible, `selectTap`/`selectHold` are disabled and the SwiftUI focus engine drives the buttons and tiles.
- Every panel is a `UIHostingController` presented `.overFullScreen`, so the focus engine works normally inside it; `.onExitCommand` (Menu) dismisses. `PanelContainer` marks its header as a `.focusSection()` so pressing Up from anywhere reaches the header buttons.
- While a panel is presented, touches, presses and the display link are ignored by the controller (`presentedViewController == nil` checks).

---

## Features in detail

| Feature | What it does | Files | Key functions |
|---|---|---|---|
| **Webby menu** | Play/Pause overlay: header (private badge, blocked count, tab count), address bar button, a navigation row and a tools row of `ChromeButton`s. Play/Pause or Menu closes it | `Webby/UI/BrowserMenuView.swift` | `BrowserViewController.presentMenu()`, `run(_:)` |
| **Start page** | Instant SwiftUI page: title, greeting/clock, search button, Favorites row, Frequently Visited row (hidden in private), Browse actions | `Webby/UI/StartPageView.swift` | `setStartPageVisible(_:)`, `LibraryStore.favorites`, `topSites` |
| **Address bar** | `.searchable` keyboard with dictation, "Go to"/"Search for" row, up to 6 suggestions, up to 8 bookmark/history matches (bookmarks ranked first) | `Webby/UI/AddressSearchView.swift` | `loadSuggestions(for:)`, `SuggestionService`, `LibraryStore.matches(for:)` |
| **Tabs** | 4-column grid of cards with snapshots; context menu to close; New, Reopen Closed, Close All. Popups/`target=_blank` open new tabs next to the current one | `Webby/UI/LibraryViews.swift`, `Webby/Browser/TabManager.swift` | `TabManager.newTab`, `close`, `closeAll`, `reopenClosedTab`, `touch` (LRU) |
| **Popup routing** | `bootstrap` overrides `window.open` and captures clicks on `a[target]` (except `_self/_parent/_top`), sending `webby://open?v=<url>` | `Webby/Browser/PageScripts.swift`, `BrowserTab.swift` | `PageScripts.bootstrap`, `BrowserTab.handleBridge` |
| **Bookmarks** | Toggling Favorite adds a bookmark with `isFavorite = true` (or removes it). Bookmarks grid with context menu: show/hide on start page, move to front, delete. First launch seeds 10 starter favourites | `Webby/UI/LibraryViews.swift`, `Webby/Store/LibraryStore.swift` | `toggleBookmark`, `toggleFavorite`, `moveToFront`, `remove`, `starterFavorites` |
| **History** | Grouped Today / Yesterday / This Week / Older; delete entries; Clear History with confirm. Capped at 400 entries, de-duplicated by `normalizedForComparison` | `Webby/UI/LibraryViews.swift`, `LibraryStore.swift` | `recordVisit`, `remove(_:)`, `clearHistory` |
| **Reader mode** | `extractArticle` scores containers by text in `<p>`s over 40 chars (×1.3 for `<article>`), needs a score of 300+, strips junk elements and all attributes except `href/src/alt`, fixes `data-src` images. The result is loaded with `loadHTML(_:baseURL:)` into a dark 34 pt template. Back/Reload/Reader again return to the source URL | `PageScripts.swift`, `BrowserTab.swift` | `toggleReader()`, `PageScripts.readerDocument` |
| **Find on Page** | Bottom bar; wraps up to 500 matches in `<mark class="__webby-find">`, adds 45vh bottom padding, steps with `scrollIntoView`, clears on Done | `Webby/UI/FindBarView.swift`, `PageScripts.swift` | `find`, `findStep`, `findClear` |
| **Dark Pages** | If the body background luminance is ≥ 0.4, injects `html{filter:invert(1) hue-rotate(180deg)}` and re-inverts media. Pages that are already dark are left alone. Engine background is set to black/white to match | `PageScripts.swift`, `BrowserTab.swift` | `darkPages(_:)`, `applyDarkPages(_:)` |
| **Zoom** | CSS `document.documentElement.style.zoom`, ±15% steps, clamped to 50–300%. Saved per display host; zooming back to the default forgets the site; not saved in private mode | `BrowserTab.swift`, `BrowserSettings.swift` | `applyZoom`, `setZoom(_:for:)`, `zoom(for:)` |
| **Native video** | `findVideos` collects non-`blob:` `<video>`/`<source>` URLs and `og:video` metas ending in mp4/m4v/mov/m3u8, pausing the page's videos. The first is played in `AVPlayerViewController` with PiP (audio session `.playback/.moviePlayback`) | `PageScripts.swift`, `BrowserViewController.swift` | `playableVideoURLs()`, `playNatively(_:)`, PiP delegate methods |
| **User agent** | Desktop (Mac Safari 18), iPad, iPhone, or the Apple TV system UA. The menu button toggles Desktop ↔ iPad. Changing it rebuilds all engines and shows a toast | `BrowserSettings.swift` | `UserAgentMode.userAgent`, `applyUserAgent()` |
| **Ad blocking** | Global `URLProtocol`; checks the host and every parent domain against `blockedDomains`; never blocks the main document itself; failed with `NSURLErrorCancelled` | `Webby/Engine/ContentBlocker.swift` | `canInit(with:)`, `shouldBlock(host:)`, `startLoading()` |
| **Private browsing** | No history, no zoom memory, no recently closed, saved session removed; Frequently Visited hidden; website data cleared on entering background | `BrowserSettings.swift`, `TabManager.swift`, `BrowserViewController.swift` | `applicationDidEnterBackground()`, `DataCleaner.clearWebsiteData()` |
| **Settings** | Search engine, home page, UA, blocking, dark pages, private, popups, restore tabs, iCloud sync, default zoom, cursor/scroll speed (Slow 1.0, Normal 1.6, Fast 2.2, Very Fast 3.0), edge scrolling, privacy actions, About (version, engine status, block-list size) | `Webby/UI/SettingsView.swift` | `DataCleaner`, `onClearData` → `rebuildAllEngines()` |
| **Controls guide** | Shown once on first launch and from the menu/settings | `SettingsView.swift` | `ControlsGuideView` |
| **Top Shelf** | Up to 12 favourites, as 800×450 tiles (site colour, favicon in a white rounded square, or a monogram) | `Webby/Store/TopShelfPublisher.swift`, `TopShelf/ContentProvider.swift`, `Shared/ShelfFavorites.swift` | `publish(_:)`, `renderTile`, `loadTopShelfContent` |
| **Deep links** | `webbytv://open?url=<http(s) url>` opens in the current tab if it's on the start page, otherwise in a new tab | `AppDelegate.swift`, `ShelfFavorites.swift` | `AppDelegate.application(_:open:options:)`, `BrowserViewController.open(_:)` |
| **Memory management** | Engines are created only when a tab is displayed; only the 4 most recently selected tabs keep live engines; on memory warning all background engines are suspended and the URL cache is purged. Suspending keeps a 640 px snapshot and the URL | `TabManager.swift`, `BrowserTab.swift` | `touch(_:)`, `suspend()`, `didReceiveMemoryWarning()` |

---

## Persistence

Everything is local `UserDefaults` (tvOS apps have no guaranteed persistent file storage beyond that), plus iCloud key-value storage for bookmarks and the app group for Top Shelf.

| Data | Where | Key(s) | Notes |
|---|---|---|---|
| Settings | `UserDefaults.standard` | `settings.searchEngine`, `settings.userAgent`, `settings.homePage`, `settings.blockAds`, `settings.privateBrowsing`, `settings.restoreTabs`, `settings.popups`, `settings.cursorSpeed`, `settings.scrollSpeed`, `settings.edgeScrolling`, `settings.defaultZoom`, `settings.showHints`, `settings.darkPages`, `settings.iCloudSync`, `settings.siteZooms` | Defaults registered in `BrowserSettings.init`: Google, **Desktop UA**, ads blocked, restore tabs, popups in new tabs, cursor 1.6, scroll 1.4, edge scrolling on, zoom 1.0, iCloud on |
| User agent | `UserDefaults.standard` registration domain | `UserAgent` | Read by the engine when it's created; not persisted (re-registered each launch) |
| Bookmarks | `UserDefaults.standard` | `library.bookmarks` (JSON `[Bookmark]`), `library.bookmarksModified`, `library.seeded` | Written to disk 1 s after a change (`scheduleSave` debounce) and pushed to iCloud immediately (`pushToCloud`) |
| History | `UserDefaults.standard` | `library.history` (JSON `[HistoryEntry]`) | 400 max; debounced save; `saveNow()` on background/terminate |
| Bookmarks (iCloud) | `NSUbiquitousKeyValueStore` | `bookmarks`, `bookmarksModified` | **Last writer wins for the whole list**, compared by modification timestamp. History is not synced |
| Tab session | `UserDefaults.standard` | `tabs.session` (JSON: tab ids, URLs, titles, selected id) | Saved on every tab change and on background; removed in private mode |
| Top Shelf | App group `group.app.webby` | `UserDefaults(suiteName:)` key `shelf.favorites`; PNG tiles in `<group container>/Shelf/` named by a djb2 hash of the URL | Written by the app, read by the extension |
| Web data | Engine/system | `HTTPCookieStorage.shared`, `URLCache.shared` (`WebbyCache`), `Library/WebKit`, `Library/Cookies`, `Caches/WebKit`, `Caches/app.webby` | Wiped by `DataCleaner.clearWebsiteData()` |

**Profiles:** the `com.apple.developer.user-management: [runs-as-current-user]` entitlement (app and extension) makes tvOS give each Apple TV user their own app container, so all of the above is per person automatically. There is no profile code in the app.

---

## External services, network and permissions

### Network calls made by the app itself

| Service | Used for | Code |
|---|---|---|
| `suggestqueries.google.com/complete/search?client=firefox` | Address bar suggestions (3 s timeout) | `SuggestionService` in `Webby/UI/AddressSearchView.swift` |
| `www.google.com/s2/favicons?domain=…` | Favicons on tiles/history/tabs (128 px) and Top Shelf tiles (256 px) | `FaviconView` in `Webby/UI/Components.swift`, `TopShelfPublisher.favicon(for:)` |
| Chosen search engine | Search result pages | `SearchEngine.searchURL(for:)` |
| iCloud key-value store | Bookmark sync | `LibraryStore` |
| App Store Connect API | Build numbers/status (scripts only, never the app) | `scripts/asc.py` |

There is no analytics, crash reporting or account system.

### Entitlements and Info.plist

| Setting | Where | Why |
|---|---|---|
| `com.apple.developer.user-management: runs-as-current-user` | Both targets | Per-user profiles |
| `com.apple.developer.ubiquity-kvstore-identifier` | App | iCloud bookmark sync (remove for free Apple IDs) |
| `com.apple.security.application-groups: group.app.webby` | Both targets | Share Top Shelf data |
| `NSAllowsArbitraryLoads`, `NSAllowsArbitraryLoadsInWebContent` | `Webby/Resources/Info.plist` | Allow plain-HTTP sites |
| `UIBackgroundModes: audio` | App `Info.plist` | Background audio playback |
| `CFBundleURLTypes: webbytv` | App `Info.plist` | Top Shelf deep links |
| `UIUserInterfaceStyle: Dark`, `ITSAppUsesNonExemptEncryption: false`, `UIRequiredDeviceCapabilities: arm64` | Both | Dark UI; export compliance; the extension needs `arm64` or App Store export rejects it |

No runtime permission prompts are requested (no camera, mic, location, local network). Dictation is the system keyboard's.

---

## Building, running, testing and releasing

**Requirements:** a Mac with Xcode 16 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen), an Apple TV running tvOS 17 or later, and a free or paid Apple Developer account.

### Build and run from Xcode

```bash
brew install xcodegen
git clone https://github.com/jleybourne/Webby.git
cd Webby
xcodegen generate
open Webby.xcodeproj
```

1. In `project.yml`, set `DEVELOPMENT_TEAM` to your own Team ID (both targets; it's currently `57PZQ6DM94`), change the bundle IDs (`app.webby`, `app.webby.topshelf`) and the app group (`group.app.webby`) to ones you own, then run `xcodegen generate` again. The app group is also hard-coded in `Shared/ShelfFavorites.swift` (`groupID`), and `app.webby` in `scripts/asc.py`, `scripts/testflight.sh` and `scripts/install-appletv.sh`. Free Apple IDs can't use iCloud: remove the `ubiquity-kvstore-identifier` entitlement and bookmarks just won't sync.
2. Pair your Apple TV: on the Apple TV, open **Settings → Remotes and Devices → Remote App and Devices**. In Xcode, open **Window → Devices and Simulators**.
3. Select your Apple TV as the run destination and press **⌘R**.

> With a free Apple ID, sideloaded apps expire after 7 days. Re-run from Xcode to refresh. A paid developer account extends this to a year.

Always edit `project.yml`, never the generated `.xcodeproj` (it's git-ignored and overwritten by `xcodegen generate`).

The tvOS Simulator can build the app, but whether `UIWebView` exists at runtime there isn't something the code checks beyond `isEngineAvailable`. A real Apple TV is the reference target.

### Command-line scripts

These sign with an App Store Connect API key instead of an Apple ID in Xcode. Put your key's details in `~/.webby-release` (outside the repo):

```
ASC_KEY_ID=XXXXXXXXXX
ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
TEAM_ID=XXXXXXXXXX
ASC_KEY_PATH=~/Downloads/AuthKey_XXXXXXXXXX.p8   # optional; this is the default
```

| Script | What it does |
|---|---|
| `scripts/install-appletv.sh [name]` | Picks the first paired Apple TV (via `xcrun devicectl list devices`) or the named one, runs `xcodegen generate`, builds Release into `build/DD-device` with `-allowProvisioningUpdates` and the API key, installs with `devicectl device install app`, and launches `app.webby` |
| `scripts/testflight.sh` | Gets the next build number from `asc.py next-build`, archives Release **unsigned** (`CODE_SIGNING_ALLOWED=NO`), re-applies entitlements with ad-hoc `codesign` (extension first, expanding `$(TeamIdentifierPrefix)`/`$(CFBundleIdentifier)` with `sed`), then `xcodebuild -exportArchive` with `destination: upload` so Apple's cloud signing signs and uploads it |
| `python3 scripts/asc.py builds` | Lists the last 20 builds and their processing state |
| `python3 scripts/asc.py next-build` | Prints the highest numeric build on App Store Connect + 1 |

`asc.py` makes its ES256 JWT with `/usr/bin/openssl` and no third-party Python packages. It needs an existing tvOS app record with bundle ID `app.webby` on App Store Connect.

Builds are local only; there's no CI (the GitHub Actions workflow was removed).

### Tests

There are no unit or UI tests and no test target. Testing is manual on a device. `BrowserSettings`, `LibraryStore` and `TabManager` all take an injectable `UserDefaults` in `init`, which would make them straightforward to unit-test if a test target is added.

### Icons

Run `bash scripts/icon/build.sh` (requires Python with Pillow and Node with Playwright). `gen.py` draws the "two panes of glass weaving into a W" SVG per layer (back, left/cyan, right/violet), `render.js` renders it with headless Chromium, and `build.sh` writes the three layered app icon stacks, the Top Shelf and Top Shelf Wide images at 1x/2x, and `docs/icon.png`.

---

## Gotchas, known issues and loose ends

Found by reading the code. None are marked `TODO`/`FIXME` in the source (there are no such comments).

### Engine and rendering

- **Private API.** Everything depends on tvOS continuing to ship `UIWebView`. There's no fallback engine.
- **The page never gets real input.** The engine has `userInteractionEnabled = NO`; clicks are synthesised in JS at the main frame's `elementFromPoint`. Consequences: content **inside iframes** (embedded players, many captchas, some payment and sign-in widgets) gets the click on the `<iframe>` element, not on what's inside it; CSS `:hover` and drag interactions don't happen; there's no text selection or copy.
- **Bootstrap runs after load,** so scripts that call `window.open` or open `target` links before `webViewDidFinishLoad` aren't routed to new tabs yet.
- **Every JS call is synchronous on the main thread.** Hover tests run up to ~8 times a second, each also evaluating `layoutMetrics`. A heavy page can make the pointer feel sticky.
- **Native video only finds direct files.** `blob:` URLs (Media Source streams, e.g. YouTube) are skipped, so many video sites report "No playable video found". Only the first URL found is played.
- **Error 102** is filtered by number alone (`nsError.code != 102`) regardless of domain.

### Settings and behaviour mismatches

- **Default user agent is Desktop,** but `UserAgentMode.appleTV.name` is "Apple TV (default)". `BrowserSettings.init` registers `UserAgentMode.desktop` as the default.
- **Switching back to Apple TV UA** in the same session registers a hard-coded placeholder string (`systemUserAgentPlaceholder`, "CPU OS 18_0"), not the real system UA. The real one only comes back after a relaunch.
- **The menu's Desktop/Mobile button** toggles Desktop ↔ iPad only; it labels the non-desktop option "Mobile Site" but picks iPad, not iPhone.
- **Suggestions always come from Google,** whichever search engine is selected, though the section header says "<engine> Suggestions". They are fetched in private mode too.
- **"Reset Everything"** clears website data and history but keeps bookmarks *and all settings*.

### Private browsing

- Private mode shares the normal cookie jar and cache. Leaving the app in private mode wipes **all** cookies and website data, so you are signed out of sites you used in normal mode too.
- Turning private on calls `saveSession()`, which **deletes** the saved normal tab session. Turning it off doesn't restore the old tabs, and the tabs opened while private are saved from then on.
- Favicon requests to Google still happen in private mode.

### Tabs, blocking and data

- Opening a 25th tab silently closes the first non-selected tab (`maxTabs = 24`).
- `suspend()` skips tabs that are still loading, so a background tab stuck loading keeps its engine past the 4-engine limit.
- `blockedCount` is incremented on **every** tab with a live engine whose host matches the blocked request's page (or on all live tabs when the request has no main document URL), so two tabs on the same site share counts.
- The block list includes whole domains like `yandex.ru`, `hotjar.com`, `optimizely.com` and `newrelic.com`. Visiting those sites works (the main document is never blocked) but their own scripts, images and styles are blocked, so they render broken.
- Third-party cookies are rejected (`.onlyFromMainDocumentDomain`), which can break embedded or cross-site sign-ins.
- Login detection needs exactly one visible password field; sign-up forms with a "confirm password" field fall back to per-field text dialogs.
- iCloud sync is last-writer-wins for the whole bookmark list, using each device's clock. Edits made on two Apple TVs close together can be lost.
- Top Shelf tiles are cached by URL forever. If the favicon fetch failed the first time, that favourite keeps its monogram tile until it's removed and re-added.
- Top Shelf item identifiers include the list index, so reordering favourites changes every identifier.

### Dead or unused code

- `BrowserAction.nextTab` / `.previousTab` are handled in `run(_:)` but nothing in the UI sends them.
- `LibraryStore.updateTitle(_:for:)` is never called.
- `Webby/Browser/CursorView.swift` also holds `StatusHUDView` and `ToastView`, which is easy to miss when looking for them.

### Repo housekeeping

- `project.yml` still contains the `DEVELOPMENT_TEAM` ID, even though the release scripts read `TEAM_ID` from `~/.webby-release`.
- No tests and no CI, so any change needs a manual check on a real Apple TV.

---

## Contributing

Issues and pull requests are welcome. Webby is a personal project, so replies may take a while.

## License

Webby is released under the [MIT License](LICENSE). It isn't affiliated with or endorsed by Apple.
