//
//  AddressSearchView.swift
//  Webby
//
//  The address bar: tvOS search keyboard (with dictation) plus live suggestions
//  from the search engine, your bookmarks and history.
//

import SwiftUI

struct AddressSearchView: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var settings: BrowserSettings
    let onSubmit: (String) -> Void
    let onOpen: (URL) -> Void
    let dismiss: () -> Void

    @State private var text = ""
    @State private var suggestions: [String] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backdrop.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if !trimmed.isEmpty {
                            resultButton(icon: looksLikeURL ? "globe" : "magnifyingglass",
                                         title: looksLikeURL ? "Go to \(trimmed)" : "Search \(settings.searchEngine.name) for “\(trimmed)”",
                                         subtitle: nil) { onSubmit(trimmed) }
                        }
                        if !suggestions.isEmpty {
                            SectionHeader(title: "\(settings.searchEngine.name) Suggestions")
                            ForEach(suggestions, id: \.self) { suggestion in
                                resultButton(icon: "magnifyingglass", title: suggestion, subtitle: nil) { onSubmit(suggestion) }
                            }
                        }
                        let local = library.matches(for: trimmed)
                        if !local.isEmpty {
                            SectionHeader(title: trimmed.isEmpty ? "Recent" : "Bookmarks & History")
                            ForEach(local) { entry in
                                resultButton(icon: "clock.arrow.circlepath",
                                             title: entry.title.isEmpty ? URLResolver.displayHost(entry.url) : entry.title,
                                             subtitle: entry.url.absoluteString) { onOpen(entry.url) }
                            }
                        }
                    }
                    .padding(.horizontal, 90)
                    .padding(.vertical, 30)
                }
            }
            .searchable(text: $text, prompt: "Search or enter website")
            .onSubmit(of: .search) { if !trimmed.isEmpty { onSubmit(trimmed) } }
            .task(id: text) { await loadSuggestions(for: text) }
        }
        .onExitCommand(perform: dismiss)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var looksLikeURL: Bool {
        let url = URLResolver.url(from: trimmed, engine: settings.searchEngine)
        return url != settings.searchEngine.searchURL(for: trimmed)
    }

    private func resultButton(icon: String, title: String, subtitle: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 24) {
                Image(systemName: icon).font(.system(size: 28, weight: .semibold)).frame(width: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 30, weight: .medium)).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 22)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.card)
    }

    private func loadSuggestions(for query: String) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, !looksLikeURL else { suggestions = []; return }
        try? await Task.sleep(nanoseconds: 220_000_000)
        guard !Task.isCancelled else { return }
        let results = await SuggestionService.suggestions(for: q)
        guard !Task.isCancelled else { return }
        suggestions = Array(results.prefix(6))
    }
}

enum SuggestionService {
    static func suggestions(for query: String) async -> [String] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .webbyQueryAllowed),
              let url = URL(string: "https://suggestqueries.google.com/complete/search?client=firefox&q=\(encoded)") else {
            return []
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count > 1, let list = json[1] as? [String] else { return [] }
        return list
    }
}
