//
//  FindBarView.swift
//  Webby
//
//  Find on Page: a bar along the bottom of the screen, with the page left visible above it.
//

import SwiftUI

struct FindBarView: View {
    /// Highlights matches and returns how many there are.
    let onFind: (String) -> Int
    /// Moves to the next (1) or previous (-1) match and returns "current/total".
    let onStep: (Int) -> String
    let dismiss: () -> Void

    @State private var text = ""
    @State private var status = ""
    @State private var hasMatches = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 24) {
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Find on Page", text: $text)
                    .focused($fieldFocused)
                    .onSubmit(search)
                    .frame(width: 720)
                Text(status)
                    .font(.system(size: 26, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 150)
                Spacer(minLength: 0)
                Button { step(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(!hasMatches)
                Button { step(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(!hasMatches)
                Button("Done", action: dismiss)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 26)
            // Opaque enough to read over any page, light or dark, with an edge to set it apart.
            .background(Color(white: 0.14).opacity(0.94), in: RoundedRectangle(cornerRadius: 40, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 40, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 2))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
            .padding(.horizontal, 80)
            .padding(.bottom, 50)
        }
        .onAppear { fieldFocused = true }
        .onExitCommand(perform: dismiss)
    }

    private func search() {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { status = ""; hasMatches = false; return }
        let count = onFind(query)
        hasMatches = count > 0
        status = hasMatches ? Self.format(onStep(1)) : "No matches"
    }

    private func step(_ delta: Int) {
        status = Self.format(onStep(delta))
    }

    /// "3/12" → "3 of 12".
    private static func format(_ position: String) -> String {
        position.replacingOccurrences(of: "/", with: " of ")
    }
}
