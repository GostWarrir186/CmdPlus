import SwiftUI

/// Плитка в стиле Пункта управления: цветной кружок с иконкой,
/// заголовок, подпись, сочетание клавиш справа и произвольное содержимое снизу.
/// Фон — Liquid Glass.
struct ModuleTile<Content: View>: View {
    let title: LocalizedStringResource
    let subtitle: String
    let systemImage: String
    let tint: Color
    var shortcut: String? = nil
    let action: () -> Void
    @ViewBuilder var content: Content

    /// Ширина колонки иконки и отступ до текста — по ним выравнивается содержимое плитки.
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

/// Сочетание клавиш в виде маленькой «клавиши». Форма — капсула,
/// она одинаково хорошо смотрится внутри любого скругления.
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

/// Иконка в цветной подложке: кружок (как в Пункте управления)
/// или скруглённый квадрат (как в Системных настройках).
struct TintedIcon: View {
    enum Style {
        case circle
        case roundedSquare
    }

    let systemImage: String
    let tint: Color
    var size: CGFloat = 22
    var style: Style = .roundedSquare

    var body: some View {
        // Символ вписывается в квадрат 58% подложки: у разных SF Symbols разные
        // пропорции и базовая линия, а так любой символ встаёт точно по центру
        // и выглядит одного размера с соседями.
        Image(systemName: systemImage)
            .resizable()
            .fontWeight(.semibold)
            .scaledToFit()
            .frame(width: size * 0.58, height: size * 0.58)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: shape)
            .accessibilityHidden(true)
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
