import SwiftUI

/// Control Center-style tile on Liquid Glass: tinted icon, title, subtitle,
/// optional shortcut, and any extra content below.
struct ModuleTile<Content: View>: View {
    let title: LocalizedStringResource
    let subtitle: String
    let systemImage: String
    let tint: Color
    var shortcut: String? = nil
    let action: () -> Void
    @ViewBuilder var content: Content

    /// Icon column width and spacing — tile content lines up with these.
    static var iconSize: CGFloat { 32 }
    static var iconSpacing: CGFloat { 10 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: action) {
                HStack(spacing: Self.iconSpacing) {
                    TintedIcon(systemImage: systemImage, tint: tint, size: Self.iconSize, style: .circle)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.headline)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if let shortcut {
                        KeyCap(text: shortcut)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            content
        }
        .padding(Design.Panel.tilePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Design.Panel.tileRadius))
    }
}

extension ModuleTile where Content == EmptyView {
    init(
        title: LocalizedStringResource,
        subtitle: String,
        systemImage: String,
        tint: Color,
        shortcut: String? = nil,
        action: @escaping () -> Void
    ) {
        self.init(
            title: title, subtitle: subtitle, systemImage: systemImage,
            tint: tint, shortcut: shortcut, action: action
        ) {
            EmptyView()
        }
    }
}

/// A keyboard shortcut drawn as a small key. A capsule fits inside any corner radius.
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: .capsule)
    }
}

/// An SF Symbol on a tinted background — a circle (Control Center) or a rounded
/// square (System Settings). Like System Settings in macOS 26, squares turn dark
/// with a tinted symbol in dark mode; circles stay colored.
struct TintedIcon: View {
    enum Style {
        case circle
        case roundedSquare
    }

    @Environment(\.colorScheme) private var colorScheme

    let systemImage: String
    let tint: Color
    var size: CGFloat = 22
    var style: Style = .roundedSquare

    var body: some View {
        // Fit the symbol into 58% of the tile. Symbols differ in proportions and
        // baseline, so this keeps every one centered and the same visual size.
        Image(systemName: systemImage)
            .resizable()
            .fontWeight(.semibold)
            .scaledToFit()
            .frame(width: size * 0.58, height: size * 0.58)
            .foregroundStyle(isDarkTile ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(.white))
            .frame(width: size, height: size)
            .background(background, in: shape)
            .overlay {
                if isDarkTile {
                    shape.stroke(.white.opacity(0.12), lineWidth: 0.5)
                }
            }
            .accessibilityHidden(true)
    }

    private var isDarkTile: Bool {
        style == .roundedSquare && colorScheme == .dark
    }

    private var background: AnyShapeStyle {
        if isDarkTile {
            AnyShapeStyle(LinearGradient(
                colors: [Color(white: 0.22), Color(white: 0.13)],
                startPoint: .top,
                endPoint: .bottom
            ))
        } else {
            AnyShapeStyle(tint.gradient)
        }
    }

    private var shape: AnyShape {
        switch style {
        case .circle:
            AnyShape(.circle)
        case .roundedSquare:
            AnyShape(.rect(cornerRadius: Design.iconRadius(for: size)))
        }
    }
}
