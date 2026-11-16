import SwiftUI

/// Shared sizes and corner radii.
///
/// Nested shapes follow the Liquid Glass rule: inner radius = outer radius − padding,
/// so corners stay concentric. That's why inner radii are computed, not hard-coded.
enum Design {
    /// Menu bar panel and its tiles.
    enum Panel {
        static let padding: CGFloat = 12
        static let tileSpacing: CGFloat = 10
        static let tileRadius: CGFloat = 22
        static let tilePadding: CGFloat = 12
        /// Row highlight inset from the tile edge.
        static let rowInset: CGFloat = 6
        static let rowRadius = tileRadius - rowInset
    }

    /// History window. Radii go inside out: thumbnail → row → window.
    enum History {
        static let windowSize = CGSize(width: 800, height: 520)
        static let listWidth: CGFloat = 320
        static let thumbnailSize: CGFloat = 28
        static let thumbnailRadius = Design.iconRadius(for: thumbnailSize)
        static let rowPadding: CGFloat = 6
        static let rowRadius = thumbnailRadius + rowPadding
        static let listPadding: CGFloat = 8
        static let windowRadius = rowRadius + listPadding
        static let previewRadius: CGFloat = 10
        /// How much the backdrop hides what's behind the window (0 = clear glass, 1 = opaque).
        static let backgroundOpacity = 0.82
    }

    /// Proportional to size like System Settings icons, so small and large look alike.
    static func iconRadius(for size: CGFloat) -> CGFloat {
        size * 0.225
    }
}
