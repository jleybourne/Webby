//
//  StartPageView.swift
//  Webby
//
//  Native start page: instant to show, fully focus-engine driven.
//

import SwiftUI

struct StartPageView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var settings: BrowserSettings
    let tabCount: Int
    let onOpen: (URL) -> Void
    let onSearch: () -> Void
    let onAction: (BrowserAction) -> Void

    var body: some View {
        ZStack {
            Theme.backdrop.ignoresSafeArea()
            RadialGradient(colors: [Theme.accent.opacity(0.28), .clear], center: .topTrailing,
                           startRadius: 40, endRadius: 1100)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 56) {
                    header
                    searchButton
                    if !library.favorites.isEmpty {
                        tileRow(title: "Favorites", items: library.favorites.map { SiteItem(id: $0.id, title: $0.title, url: $0.url) })
                    }
                    if !library.topSites.isEmpty && !settings.privateBrowsing {
                        tileRow(title: "Frequently Visited",
                                items: library.topSites.map { SiteItem(id: $0.id, title: $0.title.isEmpty ? URLResolver.displayHost($0.url) : $0.title, url: $0.url) })
                    }
                    quickActions
                }
                .padding(.horizontal, 90)
                .padding(.vertical, 70)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Webby")
                    .font(.system(size: 76, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white, Theme.accent], startPoint: .leading, endPoint: .trailing))
                Text(settings.privateBrowsing ? "Private Browsing — history and data won't be kept" : greeting)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(settings.privateBrowsing ? Color.purple : Color.secondary)
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(context.date, style: .time)
                    .font(.system(size: 54, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var searchButton: some View {
        Button(action: onSearch) {
            HStack(spacing: 24) {
                Image(systemName: "magnifyingglass").font(.system(size: 34, weight: .semibold))
                Text("Search \(settings.searchEngine.name) or enter a website")
                    .font(.system(size: 32, weight: .medium))
                Spacer()
                Image(systemName: "mic.fill").font(.system(size: 28)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.card)
    }

    private func tileRow(title: String, items: [SiteItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 40) {
                    ForEach(items) { item in
                        SiteTile(title: item.title, url: item.url) { onOpen(item.url) }
                    }
                }
                .padding(.vertical, 30)
                .padding(.horizontal, 6)
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Browse")
            HStack(spacing: 26) {
                ChromeButton(title: "Tabs (\(tabCount))", systemImage: "square.on.square") { onAction(.tabs) }
                ChromeButton(title: "Bookmarks", systemImage: "book.fill") { onAction(.bookmarks) }
                ChromeButton(title: "History", systemImage: "clock.fill") { onAction(.history) }
                ChromeButton(title: "Private", systemImage: "eye.slash.fill", tint: .purple,
                             isOn: settings.privateBrowsing) { onAction(.togglePrivate) }
                ChromeButton(title: "Controls", systemImage: "appletvremote.gen4.fill") { onAction(.controls) }
                ChromeButton(title: "Settings", systemImage: "gearshape.fill") { onAction(.settings) }
            }
            .padding(.vertical, 24)
        }
    }
}

struct SiteItem: Identifiable {
    let id: UUID
    let title: String
    let url: URL
}
