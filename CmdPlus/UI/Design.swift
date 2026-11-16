import SwiftUI

/// Единые размеры и скругления интерфейса.
///
/// Правило вложенных форм (как в Liquid Glass): у элемента внутри другого элемента
/// радиус = радиус внешнего − отступ между ними. Тогда углы идут параллельно.
/// Поэтому внутренние радиусы здесь не задаются числами, а вычисляются.
enum Design {
    /// Панель в строке меню и её плитки.
    enum Panel {
        static let padding: CGFloat = 12
        static let tileSpacing: CGFloat = 10
        static let tileRadius: CGFloat = 22
        static let tilePadding: CGFloat = 12
        /// Подсветка строки внутри плитки отступает от края плитки на столько.
        static let rowInset: CGFloat = 6
        static let rowRadius = tileRadius - rowInset
    }

    /// Окно истории в стиле Spotlight.
    /// Считаем изнутри наружу: миниатюра → строка → окно.
    enum History {
        static let thumbnailSize: CGFloat = 40
        static let thumbnailRadius = Design.iconRadius(for: thumbnailSize)
        static let rowPadding: CGFloat = 8
        static let rowRadius = thumbnailRadius + rowPadding
        static let listPadding: CGFloat = 8
        static let windowRadius = rowRadius + listPadding
    }

    /// Скругление «квадратных» иконок как у иконок Системных настроек:
    /// пропорционально размеру, поэтому маленькие и большие выглядят одинаково.
    static func iconRadius(for size: CGFloat) -> CGFloat {
        size * 0.225
    }
}
