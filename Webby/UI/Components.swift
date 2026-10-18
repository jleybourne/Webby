//
//  Components.swift
//  Webby
//
//  Shared SwiftUI building blocks for the 10-foot UI.
//

import SwiftUI

enum Theme {
    static let accent = Color(red: 0.04, green: 0.52, blue: 1.0)
    static let backdrop = LinearGradient(
        colors: [Color(red: 0.05, green: 0.06, blue: 0.11), Color(red: 0.02, green: 0.02, blue: 0.04)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Deterministic colour for a site monogram.
    static func color(for seed: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.95, green: 0.33, blue: 0.31), Color(red: 1.0, green: 0.62, blue: 0.2),
            Color(red: 0.2, green: 0.78, blue: 0.45), Color(red: 0.16, green: 0.65, blue: 0.95),
            Color(red: 0.55, green: 0.42, blue: 0.98), Color(red: 0.93, green: 0.36, blue: 0.68),
            Color(red: 0.1, green: 0.74, blue: 0.74), Color(red: 0.98, green: 0.78, blue: 0.2),
        ]
        let hash = seed.unicodeScalars.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }
}

/// Site icon fetched from a favicon service with a coloured monogram fallback.
struct FaviconView: View {
    let url: URL
    var size: CGFloat = 96

    private var host: String { URLResolver.displayHost(url) }

    private var iconURL: URL? {
        guard let host = url.host else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128")
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Theme.color(for: host).gradient)
            Text(String(host.first ?? "W").uppercased())
                .font(.system(size: size * 0.48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            AsyncImage(url: iconURL) { phase in
                if case .success(let image) = phase {
                    ZStack {
                        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(.white)
                        image.resizable().interpolation(.high).scaledToFit().padding(size * 0.18)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

/// A large tile for a website: favicon + title.
struct SiteTile: View {
    let title: String
    let url: URL
    var badge: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 18) {
                FaviconView(url: url, size: 110)
                    .overlay(alignment: .topTrailing) {
                        if let badge {
                            Image(systemName: badge)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.yellow)
                                .padding(6)
                                .background(.black.opacity(0.6), in: Circle())
                                .offset(x: 10, y: -10)
                        }
                    }
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 200)
            }
            .padding(.vertical, 26)
            .padding(.horizontal, 20)
            .frame(width: 250, height: 240)
        }
        .buttonStyle(.card)
    }
}

/// Icon + label pill used throughout the menus.
struct ChromeButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .white
    var isOn = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChromeButtonLabel(title: title, systemImage: systemImage, tint: tint, isOn: isOn)
        }
        .buttonStyle(ChromeButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

private struct ChromeButtonLabel: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isOn: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(isFocused ? Color.black : (isOn ? Theme.accent : tint))
                .frame(height: 46)
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isFocused ? Color.black : Color.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 150, height: 130)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isFocused ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(isOn ? 0.18 : 0.08)))
        )
        .scaleEffect(isFocused ? 1.1 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.45 : 0), radius: 18, y: 10)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isFocused)
    }
}

struct ChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Heavy blur plus a dark tint, so whatever is underneath (a bright web page, the
/// start page's own title and search bar) reads as soft colour, never as content.
struct OverlayBackdrop: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.thickMaterial)
            LinearGradient(colors: [.black.opacity(0.78), .black.opacity(0.62)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

/// A button label for destructive actions. Only the icon is red: tvOS's destructive
/// role draws red text on a light-red fill, which is hard to read.
struct DestructiveLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(.red)
        }
    }
}

/// Full-screen frosted panel with a title row; Menu closes it.
struct PanelContainer<Content: View, Accessory: View>: View {
    let title: String
    let dismiss: () -> Void
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            OverlayBackdrop()
            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .center) {
                    Text(title)
                        .font(.system(size: 56, weight: .bold))
                    Spacer()
                    accessory()
                }
                // The header spans the full width, so as a focus section it catches
                // Up from content anywhere below and hands focus to the buttons.
                .focusSection()
                content()
            }
            .padding(.horizontal, 90)
            .padding(.top, 60)
        }
        .onExitCommand(perform: dismiss)
    }
}

extension PanelContainer where Accessory == EmptyView {
    init(title: String, dismiss: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.dismiss = dismiss
        self.accessory = { EmptyView() }
        self.content = content
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 24, weight: .bold))
            .tracking(2)
            .foregroundStyle(.secondary)
    }
}
