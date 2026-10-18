//
//  LibraryViews.swift
//  Webby
//
//  Tab switcher, bookmarks and history panels.
//

import SwiftUI

// MARK: - Tabs

struct TabSwitcherView: View {
    @ObservedObject var tabManager: TabManager
    let onSelect: (BrowserTab) -> Void
    let onNewTab: () -> Void
    let onReopen: () -> Void
    let dismiss: () -> Void

    private let columns = Array(repeating: GridItem(.fixed(380), spacing: 50), count: 4)

    var body: some View {
        PanelContainer(title: "Tabs", dismiss: dismiss) {
            HStack(spacing: 24) {
                Button { onNewTab() } label: { Label("New Tab", systemImage: "plus") }
                if !tabManager.recentlyClosed.isEmpty {
                    Button { onReopen() } label: { Label("Reopen Closed Tab", systemImage: "arrow.uturn.backward") }
                }
                Button { tabManager.closeAll(); dismiss() } label: {
                    DestructiveLabel("Close All", systemImage: "xmark")
                }
            }
        } content: {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 60) {
                    ForEach(tabManager.tabs) { tab in
                        TabCard(tab: tab, isSelected: tab.id == tabManager.selectedTab?.id) { onSelect(tab) }
                            .contextMenu {
                                Button(role: .destructive) { tabManager.close(tab) } label: {
                                    Label("Close Tab", systemImage: "xmark")
                                }
                            }
                    }
                }
                .padding(.vertical, 40)
            }
            // Let the focused card's lift effect draw past the scroll view's edges.
            .scrollClipDisabled()
        }
    }
}

private struct TabCard: View {
    @ObservedObject var tab: BrowserTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Color.black
                    if let snapshot = tab.snapshot, tab.url != nil {
                        Image(uiImage: snapshot).resizable().scaledToFill()
                    } else if let url = tab.url {
                        FaviconView(url: url, size: 90)
                    } else {
                        Image(systemName: "house.fill").font(.system(size: 60)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 380, height: 214)
                .clipped()
                HStack(spacing: 12) {
                    if isSelected { Circle().fill(Theme.accent).frame(width: 12, height: 12) }
                    Text(tab.displayTitle).font(.system(size: 22, weight: .semibold)).lineLimit(1)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(width: 380, alignment: .leading)
            }
        }
        .buttonStyle(.card)
    }
}

// MARK: - Bookmarks

struct BookmarksView: View {
    @ObservedObject var library: LibraryStore
    let onOpen: (URL) -> Void
    let dismiss: () -> Void

    private let columns = Array(repeating: GridItem(.fixed(250), spacing: 40), count: 6)

    var body: some View {
        PanelContainer(title: "Bookmarks", dismiss: dismiss) {
            if library.bookmarks.isEmpty {
                emptyState(icon: "star", text: "Press Play/Pause on any page and choose Favorite to save it here.")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 50) {
                        ForEach(library.bookmarks) { bookmark in
                            SiteTile(title: bookmark.title, url: bookmark.url,
                                     badge: bookmark.isFavorite ? "star.fill" : nil) { onOpen(bookmark.url) }
                                .contextMenu {
                                    Button { library.toggleFavorite(bookmark) } label: {
                                        Label(bookmark.isFavorite ? "Remove from Start Page" : "Show on Start Page",
                                              systemImage: bookmark.isFavorite ? "star.slash" : "star")
                                    }
                                    Button { library.moveToFront(bookmark) } label: {
                                        Label("Move to Front", systemImage: "arrow.left.to.line")
                                    }
                                    Button(role: .destructive) { library.remove(bookmark) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 40)
                }
                .scrollClipDisabled()
                Text("Press and hold a bookmark for more options.")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - History

struct HistoryView: View {
    @ObservedObject var library: LibraryStore
    let onOpen: (URL) -> Void
    let dismiss: () -> Void

    @State private var confirmClear = false

    var body: some View {
        PanelContainer(title: "History", dismiss: dismiss) {
            if !library.history.isEmpty {
                Button { confirmClear = true } label: {
                    DestructiveLabel("Clear History", systemImage: "trash")
                }
            }
        } content: {
            if library.history.isEmpty {
                emptyState(icon: "clock", text: "Pages you visit will appear here.")
            } else {
                List {
                    ForEach(groups, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.entries) { entry in
                                Button { onOpen(entry.url) } label: { row(entry) }
                                    .contextMenu {
                                        Button(role: .destructive) { library.remove(entry) } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
            }
        }
        .alert("Clear all browsing history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { library.clearHistory() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 24) {
            FaviconView(url: entry.url, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title.isEmpty ? URLResolver.displayHost(entry.url) : entry.title)
                    .font(.system(size: 28, weight: .medium)).lineLimit(1)
                Text(entry.url.absoluteString).font(.system(size: 20)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(entry.lastVisited, style: .time).font(.system(size: 22)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private struct HistoryGroup { let title: String; let entries: [HistoryEntry] }

    private var groups: [HistoryGroup] {
        let calendar = Calendar.current
        var today: [HistoryEntry] = [], yesterday: [HistoryEntry] = [], week: [HistoryEntry] = [], older: [HistoryEntry] = []
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        for entry in library.history {
            if calendar.isDateInToday(entry.lastVisited) { today.append(entry) }
            else if calendar.isDateInYesterday(entry.lastVisited) { yesterday.append(entry) }
            else if entry.lastVisited > weekAgo { week.append(entry) }
            else { older.append(entry) }
        }
        return [HistoryGroup(title: "Today", entries: today), HistoryGroup(title: "Yesterday", entries: yesterday),
                HistoryGroup(title: "This Week", entries: week), HistoryGroup(title: "Older", entries: older)]
            .filter { !$0.entries.isEmpty }
    }
}

@ViewBuilder
func emptyState(icon: String, text: String) -> some View {
    VStack(spacing: 26) {
        Spacer()
        Image(systemName: icon).font(.system(size: 90)).foregroundStyle(.secondary)
        Text(text).font(.system(size: 30)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        Spacer()
    }
    .frame(maxWidth: .infinity)
}
