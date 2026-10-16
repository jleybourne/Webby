//
//  BrowserMenuView.swift
//  Webby
//
//  The Play/Pause menu: page info plus every browser action, laid out for the focus engine.
//

import SwiftUI

enum BrowserAction {
    case back, forward, reload, stop, home, search, newTab, closeTab, tabs
    case toggleBookmark, bookmarks, history, settings
    case reader, playVideo, zoomIn, zoomOut, zoomReset
    case toggleMode, toggleDesktop, togglePrivate, controls
    case nextTab, previousTab
}

struct MenuState {
    var title: String
    var url: URL?
    var canGoBack: Bool
    var canGoForward: Bool
    var isLoading: Bool
    var isBookmarked: Bool
    var isReaderActive: Bool
    var isStartPage: Bool
    var blockedCount: Int
    var zoom: Double
    var mode: InputMode
    var userAgent: UserAgentMode
    var tabCount: Int
    var isPrivate: Bool
}

struct BrowserMenuView: View {
    let state: MenuState
    let onAction: (BrowserAction) -> Void
    let onDismiss: () -> Void

    @FocusState private var focusedSearch: Bool

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.92), .black.opacity(0.75), .black.opacity(0.1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 34) {
                header
                addressBar
                row(navigationButtons)
                row(toolButtons)
            }
            .padding(.horizontal, 80)
            .padding(.top, 50)
        }
        .onExitCommand(perform: onDismiss)
        .onPlayPauseCommand(perform: onDismiss)
        .onAppear { focusedSearch = true }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text("Webby")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.accent)
            if state.isPrivate {
                Label("Private", systemImage: "eye.slash.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.purple)
            }
            Spacer()
            if state.blockedCount > 0 {
                Label("\(state.blockedCount) blocked", systemImage: "shield.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.green)
            }
            Label("\(state.tabCount) \(state.tabCount == 1 ? "tab" : "tabs")", systemImage: "square.on.square")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var addressBar: some View {
        Button { onAction(.search) } label: {
            HStack(spacing: 18) {
                Image(systemName: state.url?.scheme == "https" ? "lock.fill" : "magnifyingglass")
                    .font(.system(size: 28, weight: .semibold))
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.isStartPage ? "Search or enter website" : state.title)
                        .font(.system(size: 30, weight: .semibold))
                        .lineLimit(1)
                    if let url = state.url {
                        Text(url.absoluteString)
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "mic.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.card)
        .focused($focusedSearch)
    }

    private func row(_ buttons: [AnyView]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 26) {
                ForEach(buttons.indices, id: \.self) { buttons[$0] }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 10)
        }
    }

    private var navigationButtons: [AnyView] {
        [
            AnyView(ChromeButton(title: "Back", systemImage: "chevron.backward", isEnabled: state.canGoBack) { onAction(.back) }),
            AnyView(ChromeButton(title: "Forward", systemImage: "chevron.forward", isEnabled: state.canGoForward) { onAction(.forward) }),
            state.isLoading
                ? AnyView(ChromeButton(title: "Stop", systemImage: "xmark") { onAction(.stop) })
                : AnyView(ChromeButton(title: "Reload", systemImage: "arrow.clockwise", isEnabled: !state.isStartPage) { onAction(.reload) }),
            AnyView(ChromeButton(title: "Home", systemImage: "house.fill") { onAction(.home) }),
            AnyView(ChromeButton(title: "Tabs", systemImage: "square.on.square") { onAction(.tabs) }),
            AnyView(ChromeButton(title: "New Tab", systemImage: "plus.square.on.square") { onAction(.newTab) }),
            AnyView(ChromeButton(title: state.isBookmarked ? "Favorited" : "Favorite",
                                 systemImage: state.isBookmarked ? "star.fill" : "star",
                                 tint: .yellow, isOn: state.isBookmarked,
                                 isEnabled: state.url != nil) { onAction(.toggleBookmark) }),
            AnyView(ChromeButton(title: "Bookmarks", systemImage: "book.fill") { onAction(.bookmarks) }),
            AnyView(ChromeButton(title: "History", systemImage: "clock.fill") { onAction(.history) }),
            AnyView(ChromeButton(title: "Close Tab", systemImage: "xmark.square") { onAction(.closeTab) }),
        ]
    }

    private var toolButtons: [AnyView] {
        [
            AnyView(ChromeButton(title: state.mode == .cursor ? "Scroll Mode" : "Cursor Mode",
                                 systemImage: state.mode == .cursor ? "arrow.up.and.down" : "circle.circle") { onAction(.toggleMode) }),
            AnyView(ChromeButton(title: "Reader", systemImage: "doc.plaintext", isOn: state.isReaderActive,
                                 isEnabled: !state.isStartPage) { onAction(.reader) }),
            AnyView(ChromeButton(title: "Play Video", systemImage: "play.rectangle.fill",
                                 isEnabled: !state.isStartPage) { onAction(.playVideo) }),
            AnyView(ChromeButton(title: "Zoom Out", systemImage: "minus.magnifyingglass") { onAction(.zoomOut) }),
            AnyView(ChromeButton(title: "\(Int((state.zoom * 100).rounded()))%", systemImage: "textformat.size") { onAction(.zoomReset) }),
            AnyView(ChromeButton(title: "Zoom In", systemImage: "plus.magnifyingglass") { onAction(.zoomIn) }),
            AnyView(ChromeButton(title: state.userAgent == .desktop ? "Mobile Site" : "Desktop Site",
                                 systemImage: state.userAgent == .desktop ? "ipad" : "desktopcomputer") { onAction(.toggleDesktop) }),
            AnyView(ChromeButton(title: "Private", systemImage: "eye.slash.fill", tint: .purple,
                                 isOn: state.isPrivate) { onAction(.togglePrivate) }),
            AnyView(ChromeButton(title: "Controls", systemImage: "appletvremote.gen4.fill") { onAction(.controls) }),
            AnyView(ChromeButton(title: "Settings", systemImage: "gearshape.fill") { onAction(.settings) }),
        ]
    }
}
