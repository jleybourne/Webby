//
//  SettingsView.swift
//  Webby
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: BrowserSettings
    @ObservedObject var library: LibraryStore
    let onClearData: () -> Void
    let onShowControls: () -> Void
    let dismiss: () -> Void

    @State private var status: String?
    @State private var confirmClearAll = false

    private let speeds: [(String, Double)] = [("Slow", 1.0), ("Normal", 1.6), ("Fast", 2.2), ("Very Fast", 3.0)]
    private let zooms: [Double] = [0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        NavigationStack {
            Form {
                Section("Search") {
                    Picker("Search Engine", selection: $settings.searchEngine) {
                        ForEach(SearchEngine.allCases) { Text($0.name).tag($0) }
                    }
                    TextField("Home Page (blank = Start Page)", text: $settings.homePage)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Browsing") {
                    Picker("Request Websites As", selection: $settings.userAgentMode) {
                        ForEach(UserAgentMode.allCases) { Text($0.name).tag($0) }
                    }
                    Toggle("Block Ads & Trackers", isOn: $settings.blockAds)
                    Toggle("Private Browsing", isOn: $settings.privateBrowsing)
                    Toggle("Open Pop-ups in New Tabs", isOn: $settings.openPopupsInNewTab)
                    Toggle("Restore Tabs on Launch", isOn: $settings.restoreTabs)
                    Picker("Default Page Zoom", selection: $settings.defaultZoom) {
                        ForEach(zooms, id: \.self) { Text("\(Int(($0 * 100).rounded()))%").tag($0) }
                    }
                }

                Section("Siri Remote") {
                    Picker("Cursor Speed", selection: $settings.cursorSpeed) {
                        ForEach(speeds.indices, id: \.self) { Text(speeds[$0].0).tag(speeds[$0].1) }
                    }
                    Picker("Scroll Speed", selection: $settings.scrollSpeed) {
                        ForEach(speeds.indices, id: \.self) { Text(speeds[$0].0).tag(speeds[$0].1) }
                    }
                    Toggle("Scroll at Screen Edges", isOn: $settings.edgeScrolling)
                    Button("Remote Controls Guide", action: onShowControls)
                }

                Section {
                    Button("Clear Cookies & Website Data") {
                        DataCleaner.clearWebsiteData()
                        onClearData()
                        status = "Website data cleared."
                    }
                    Button("Clear History") {
                        library.clearHistory()
                        status = "History cleared."
                    }
                    Button("Reset Everything", role: .destructive) { confirmClearAll = true }
                } header: {
                    Text("Privacy")
                } footer: {
                    if let status { Text(status).foregroundStyle(.green) }
                }

                Section("About") {
                    LabeledContent("Version", value: Self.version)
                    LabeledContent("Engine", value: WBWebView.isEngineAvailable ? "WebKit (Safari)" : "Unavailable")
                    LabeledContent("Trackers on block list", value: "\(ContentBlocker.blockedDomains.count)")
                }
            }
            .navigationTitle("Settings")
        }
        .onExitCommand(perform: dismiss)
        .alert("Reset Webby?", isPresented: $confirmClearAll) {
            Button("Reset", role: .destructive) {
                DataCleaner.clearWebsiteData()
                library.clearHistory()
                onClearData()
                status = "Webby has been reset."
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clears cookies, caches, website data and history. Bookmarks are kept.")
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

// MARK: - Controls guide

struct ControlsGuideView: View {
    let dismiss: () -> Void

    private let rows: [(String, String, String)] = [
        ("hand.draw.fill", "Swipe", "Move the pointer — or scroll the page in Scroll mode"),
        ("hand.tap.fill", "Click", "Click links, buttons and text fields under the pointer"),
        ("hand.point.up.left.fill", "Click & Hold", "Switch between Cursor and Scroll mode"),
        ("playpause.fill", "Play / Pause", "Open the Webby menu: address bar, tabs, favorites & tools"),
        ("arrow.uturn.backward", "Back / Menu", "Go back a page. On the start page, return to your page"),
        ("arrow.up.and.down.and.arrow.left.and.right", "D-pad Edges", "Jump a page up, down, left or right"),
        ("rectangle.portrait.arrowtriangle.2.outward", "Screen Edges", "Push the pointer to an edge to scroll that way"),
    ]

    var body: some View {
        PanelContainer(title: "Siri Remote Controls", dismiss: dismiss) {
            VStack(alignment: .leading, spacing: 30) {
                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]
                    HStack(spacing: 36) {
                        Image(systemName: row.0)
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 80)
                        Text(row.1).font(.system(size: 34, weight: .bold)).frame(width: 300, alignment: .leading)
                        Text(row.2).font(.system(size: 30)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack {
                    Spacer()
                    Button("Start Browsing", action: dismiss)
                        .font(.system(size: 32, weight: .semibold))
                    Spacer()
                }
                .padding(.bottom, 60)
            }
            .padding(.top, 20)
        }
    }
}

// MARK: - Data cleaning

enum DataCleaner {
    static func clearWebsiteData() {
        let storage = HTTPCookieStorage.shared
        storage.cookies?.forEach(storage.deleteCookie)
        URLCache.shared.removeAllCachedResponses()

        let fm = FileManager.default
        var targets: [URL] = []
        if let library = fm.urls(for: .libraryDirectory, in: .userDomainMask).first {
            targets.append(library.appendingPathComponent("WebKit"))
            targets.append(library.appendingPathComponent("Cookies"))
        }
        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            targets.append(caches.appendingPathComponent("WebKit"))
            if let bundleID = Bundle.main.bundleIdentifier {
                targets.append(caches.appendingPathComponent(bundleID))
            }
        }
        targets.forEach { try? fm.removeItem(at: $0) }
    }
}
