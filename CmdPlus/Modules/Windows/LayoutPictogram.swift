import SwiftUI

/// A tiny screen with the area the action fills highlighted. Drawn from the
/// same math that moves windows, so the picture always matches the result.
struct LayoutPictogram: View {
    let action: WindowAction
    var size = CGSize(width: 46, height: 30)

    var body: some View {
        let screen = CGRect(origin: .zero, size: size)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.primary.opacity(0.08))
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)

            if let regions = Self.regions(for: action, in: screen) {
                ForEach(Array(regions.enumerated()), id: \.offset) { index, rect in
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.accentColor.opacity(index == 0 ? 0.9 : 0.55))
                        .overlay {
                            if regions.count > 1 {
                                Text(verbatim: "\(index + 1)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            } else {
                Image(systemName: action.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Highlighted areas in SwiftUI coordinates (origin top-left), or `nil`
    /// for actions better shown as a symbol.
    static func regions(for action: WindowAction, in screen: CGRect) -> [CGRect]? {
        let layouts = action.arrangement ?? [action]
        let inner = screen.insetBy(dx: 2.5, dy: 2.5)
        let window = CGRect(x: inner.midX - inner.width * 0.25, y: inner.midY - inner.height * 0.25,
                            width: inner.width * 0.5, height: inner.height * 0.5)
        let frames = layouts.compactMap { $0.rawFrame(in: inner, current: window, gap: 1.5) }
        guard frames.count == layouts.count else { return nil }
        // Layout math uses a bottom-left origin; flip for drawing.
        return frames.map { CGRect(x: $0.minX, y: screen.height - $0.maxY, width: $0.width, height: $0.height) }
    }
}
