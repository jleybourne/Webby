<p align="center"><img src="docs/icon.png" width="400" alt="Webby icon"></p>

# Webby

**A fast, native web browser for Apple TV, built on Safari's WebKit engine.**

Webby drives the WebKit engine that ships inside tvOS directly from the Siri Remote. It has a smooth adaptive pointer, inertial scrolling, tabs, favorites and network-level ad blocking, and its 10-foot interface is built with SwiftUI.

## Features

| | |
|---|---|
| 🖱️ **Adaptive pointer** | iPadOS-style cursor that grows and tints over links and buttons. Movement speeds up the faster you swipe. |
| 📜 **Scroll mode** | Hold Click to switch. Swipe to scroll with momentum, like a trackpad. |
| ↕️ **Edge and D-pad scrolling** | Push the pointer against a screen edge, or click the D-pad edges, to page around. |
| ⌨️ **Real form input** | Clicking a text field opens the tvOS keyboard (with dictation). Dropdowns become native pickers. Choose *Go* to submit forms. |
| 🗂️ **Tabs** | Visual tab switcher with live thumbnails. Pop-ups and `target=_blank` links open in new tabs. Tabs are restored on launch, and idle tabs are suspended automatically to save memory. |
| ⭐ **Favorites and bookmarks** | One-click favoriting, a favorites grid on the start page, and a "Frequently Visited" row. |
| 🕘 **History** | Grouped by day. You can search it from the address bar. |
| 🔎 **Smart address bar** | tvOS search keyboard with live suggestions from your search engine, bookmarks and history. Choose Google, DuckDuckGo, Bing, Brave or Ecosia. |
| 🛡️ **Ad and tracker blocking** | About 170 ad and tracker networks are blocked before any request leaves the device. A live counter shows what was blocked on each page. |
| 📖 **Reader mode** | Strips articles down to large, TV-legible text. |
| ▶️ **Native video** | Sends a page's video to the system AVPlayer for full Siri Remote scrubbing. |
| 🔍 **Page zoom** | Zoom from 50% to 300%. You can set a default zoom level. |
| 🖥️ **Desktop / mobile sites** | Switch user agent: Mac Safari, iPad, iPhone or Apple TV. |
| 🕶️ **Private browsing** | No history and no saved tabs. Website data is wiped when you leave the app. |
| ⚡ **Built for speed** | Native start page that appears instantly, a 256 MB shared HTTP cache, lazily created engines, and LRU suspension of background tabs. |

## Siri Remote controls

| Input | Action |
|---|---|
| Swipe | Move pointer / scroll (Scroll mode) |
| Click | Click under pointer |
| Click & hold | Toggle Cursor ↔ Scroll mode |
| Play/Pause | Open the Webby menu (address bar, tabs, favorites, tools) |
| Back / Menu | Go back; leave Scroll mode; close a tab with no history |
| D-pad edges | Page up / down / left / right |

## Building and installing

**Requirements:** a Mac with Xcode 16 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen), an Apple TV running tvOS 17 or later, and a free or paid Apple Developer account.

```bash
brew install xcodegen
git clone https://github.com/jleybourne/Webby.git
cd Webby
xcodegen generate
open Webby.xcodeproj
```

1. In Xcode, select the **Webby** target, open **Signing & Capabilities**, and choose your Team. Change the bundle ID if it's already taken.
2. Pair your Apple TV: on the Apple TV, open **Settings → Remotes and Devices → Remote App and Devices**. In Xcode, open **Window → Devices and Simulators**.
3. Select your Apple TV as the run destination and press **⌘R**.

> With a free Apple ID, sideloaded apps expire after 7 days. Re-run from Xcode to refresh. A paid developer account extends this to a year.

### App Store note

tvOS doesn't offer a public web view. Webby loads the WebKit-backed `UIWebView` class that ships inside tvOS at runtime, through a small Objective-C wrapper (`Webby/Engine/WBWebView.m`). This works for personal and sideloaded installs, but **App Review won't accept it**. If a future tvOS release removes the class, Webby detects that and tells you, rather than crashing.

## Project layout

```
Webby/
├── App/            AppDelegate: cache, content blocker, user agent bootstrap
├── Engine/         WBWebView (Obj-C runtime wrapper), ContentBlocker (URLProtocol)
├── Browser/        BrowserViewController (remote input, pointer, scrolling), tabs, injected JS
├── Store/          Settings, bookmarks and history persistence
├── UI/             SwiftUI: menu, start page, address bar, tabs, bookmarks, history, settings
└── Resources/      Info.plist, layered app icon and Top Shelf images
```

CI (`.github/workflows/build.yml`) builds every push for the tvOS Simulator and for devices.
To regenerate the icons, run `python3 scripts/generate_icons.py .` (requires Pillow).
