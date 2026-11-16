import Carbon.HIToolbox
import CoreGraphics
import SwiftUI

/// A window layout or move.
nonisolated enum WindowAction: String, CaseIterable, Identifiable, Sendable, Codable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird
    case leftTwoThirds, rightTwoThirds
    case maximize, almostMaximize, center
    case leftAndRight, rightAndLeft, topAndBottom, bottomAndTop, quarters
    case restore, nextDisplay

    var id: String { rawValue }

    /// Sections, in order — grouped like macOS's own Window → Move & Resize menu.
    static let groups: [(title: LocalizedStringResource, actions: [WindowAction])] = [
        ("Halves", [.leftHalf, .rightHalf, .topHalf, .bottomHalf]),
        ("Quarters", [.topLeft, .topRight, .bottomLeft, .bottomRight]),
        ("Thirds", [.leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds]),
        ("Arrange", [.leftAndRight, .rightAndLeft, .topAndBottom, .bottomAndTop, .quarters]),
        ("Size", [.maximize, .almostMaximize, .center, .nextDisplay, .restore]),
    ]

    /// "Arrange" actions lay out several of the frontmost windows at once.
    var arrangement: [WindowAction]? {
        switch self {
        case .leftAndRight: [.leftHalf, .rightHalf]
        case .rightAndLeft: [.rightHalf, .leftHalf]
        case .topAndBottom: [.topHalf, .bottomHalf]
        case .bottomAndTop: [.bottomHalf, .topHalf]
        case .quarters: [.topLeft, .topRight, .bottomLeft, .bottomRight]
        default: nil
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .leftHalf: "Left"
        case .rightHalf: "Right"
        case .topHalf: "Top"
        case .bottomHalf: "Bottom"
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        case .leftThird: "Left Third"
        case .centerThird: "Center Third"
        case .rightThird: "Right Third"
        case .leftTwoThirds: "Left Two Thirds"
        case .rightTwoThirds: "Right Two Thirds"
        case .maximize: "Maximize"
        case .almostMaximize: "Almost Maximize"
        case .center: "Center"
        case .leftAndRight: "Left & Right"
        case .rightAndLeft: "Right & Left"
        case .topAndBottom: "Top & Bottom"
        case .bottomAndTop: "Bottom & Top"
        case .quarters: "Quarters"
        case .restore: "Return to Previous Size"
        case .nextDisplay: "Next Display"
        }
    }

    /// Shorter name for tight spots like the menu bar grid.
    var shortTitle: LocalizedStringResource {
        self == .restore ? "Previous Size" : title
    }

    var systemImage: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.filled"
        case .rightHalf: "rectangle.righthalf.filled"
        case .topHalf: "rectangle.tophalf.filled"
        case .bottomHalf: "rectangle.bottomhalf.filled"
        case .topLeft: "rectangle.inset.topleft.filled"
        case .topRight: "rectangle.inset.topright.filled"
        case .bottomLeft: "rectangle.inset.bottomleft.filled"
        case .bottomRight: "rectangle.inset.bottomright.filled"
        case .leftThird: "rectangle.leadingthird.inset.filled"
        case .centerThird: "rectangle.center.inset.filled"
        case .rightThird: "rectangle.trailingthird.inset.filled"
        case .leftTwoThirds: "rectangle.leadinghalf.inset.filled"
        case .rightTwoThirds: "rectangle.trailinghalf.inset.filled"
        case .maximize: "rectangle.inset.filled"
        case .almostMaximize: "rectangle.dashed"
        case .center: "rectangle.center.inset.filled"
        case .leftAndRight, .rightAndLeft: "rectangle.split.2x1"
        case .topAndBottom, .bottomAndTop: "rectangle.split.1x2"
        case .quarters: "rectangle.split.2x2"
        case .restore: "arrow.uturn.backward"
        case .nextDisplay: "display.2"
        }
    }

    /// Same defaults as Rectangle, so people switching feel at home.
    var defaultShortcut: KeyCombo? {
        let ctrlOpt: CGEventFlags = [.maskControl, .maskAlternate]
        switch self {
        case .leftHalf: return KeyCombo(kVK_LeftArrow, ctrlOpt)
        case .rightHalf: return KeyCombo(kVK_RightArrow, ctrlOpt)
        case .topHalf: return KeyCombo(kVK_UpArrow, ctrlOpt)
        case .bottomHalf: return KeyCombo(kVK_DownArrow, ctrlOpt)
        case .topLeft: return KeyCombo(kVK_ANSI_U, ctrlOpt)
        case .topRight: return KeyCombo(kVK_ANSI_I, ctrlOpt)
        case .bottomLeft: return KeyCombo(kVK_ANSI_J, ctrlOpt)
        case .bottomRight: return KeyCombo(kVK_ANSI_K, ctrlOpt)
        case .leftThird: return KeyCombo(kVK_ANSI_D, ctrlOpt)
        case .centerThird: return KeyCombo(kVK_ANSI_F, ctrlOpt)
        case .rightThird: return KeyCombo(kVK_ANSI_G, ctrlOpt)
        case .leftTwoThirds: return KeyCombo(kVK_ANSI_E, ctrlOpt)
        case .rightTwoThirds: return KeyCombo(kVK_ANSI_T, ctrlOpt)
        case .maximize: return KeyCombo(kVK_Return, ctrlOpt)
        case .almostMaximize: return nil
        case .center: return KeyCombo(kVK_ANSI_C, ctrlOpt)
        case .leftAndRight: return KeyCombo(kVK_LeftArrow, ctrlOpt.union(.maskShift))
        case .rightAndLeft: return KeyCombo(kVK_RightArrow, ctrlOpt.union(.maskShift))
        case .topAndBottom: return KeyCombo(kVK_UpArrow, ctrlOpt.union(.maskShift))
        case .bottomAndTop: return KeyCombo(kVK_DownArrow, ctrlOpt.union(.maskShift))
        case .quarters: return KeyCombo(kVK_ANSI_Q, ctrlOpt.union(.maskShift))
        case .restore: return KeyCombo(kVK_Delete, ctrlOpt)
        case .nextDisplay: return KeyCombo(kVK_RightArrow, ctrlOpt.union(.maskCommand))
        }
    }

    /// Target frame inside a screen's visible area, in Cocoa coordinates
    /// (origin at the bottom left). `nil` for actions that aren't a layout.
    func frame(in screen: CGRect, current: CGRect, gap: CGFloat) -> CGRect? {
        rawFrame(in: screen, current: current, gap: gap).map(Self.aligned)
    }

    /// Windows sit on whole points. Rounding the edges (not the sizes) keeps
    /// gaps between neighbors exactly equal.
    private static func aligned(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded(), maxX = rect.maxX.rounded()
        let minY = rect.minY.rounded(), maxY = rect.maxY.rounded()
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Unrounded layout math — also used to draw tiny previews.
    func rawFrame(in screen: CGRect, current: CGRect, gap: CGFloat) -> CGRect? {
        let area = screen.insetBy(dx: gap, dy: gap)
        let halfW = (area.width - gap) / 2
        let halfH = (area.height - gap) / 2
        let thirdW = (area.width - 2 * gap) / 3

        switch self {
        case .leftHalf: return CGRect(x: area.minX, y: area.minY, width: halfW, height: area.height)
        case .rightHalf: return CGRect(x: area.maxX - halfW, y: area.minY, width: halfW, height: area.height)
        case .topHalf: return CGRect(x: area.minX, y: area.maxY - halfH, width: area.width, height: halfH)
        case .bottomHalf: return CGRect(x: area.minX, y: area.minY, width: area.width, height: halfH)
        case .topLeft: return CGRect(x: area.minX, y: area.maxY - halfH, width: halfW, height: halfH)
        case .topRight: return CGRect(x: area.maxX - halfW, y: area.maxY - halfH, width: halfW, height: halfH)
        case .bottomLeft: return CGRect(x: area.minX, y: area.minY, width: halfW, height: halfH)
        case .bottomRight: return CGRect(x: area.maxX - halfW, y: area.minY, width: halfW, height: halfH)
        case .leftThird: return CGRect(x: area.minX, y: area.minY, width: thirdW, height: area.height)
        case .centerThird: return CGRect(x: area.minX + thirdW + gap, y: area.minY, width: thirdW, height: area.height)
        case .rightThird: return CGRect(x: area.maxX - thirdW, y: area.minY, width: thirdW, height: area.height)
        case .leftTwoThirds:
            return CGRect(x: area.minX, y: area.minY, width: area.width - thirdW - gap, height: area.height)
        case .rightTwoThirds:
            return CGRect(x: area.minX + thirdW + gap, y: area.minY, width: area.width - thirdW - gap, height: area.height)
        case .maximize: return area
        case .almostMaximize:
            return area.insetBy(dx: area.width * 0.05, dy: area.height * 0.05)
        case .center:
            let width = min(current.width, area.width)
            let height = min(current.height, area.height)
            return CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
        case .restore, .nextDisplay, .leftAndRight, .rightAndLeft, .topAndBottom, .bottomAndTop, .quarters:
            return nil
        }
    }
}

/// Space between windows and screen edges.
nonisolated enum WindowGap: String, CaseIterable, Identifiable, Sendable {
    case none, small, large

    var id: String { rawValue }

    var points: CGFloat {
        switch self {
        case .none: 0
        case .small: 6
        case .large: 14
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .none: "None"
        case .small: "Small"
        case .large: "Large"
        }
    }
}

/// Converts between Cocoa screen coordinates (origin bottom-left of the main
/// screen) and Accessibility coordinates (origin top-left of the main screen).
nonisolated enum ScreenCoordinates {
    static func flip(_ rect: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Keeps a window's place and relative size when moving it to another screen.
    static func move(_ window: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        let scaleX = target.width / source.width
        let scaleY = target.height / source.height
        let width = min(window.width * scaleX, target.width)
        let height = min(window.height * scaleY, target.height)
        var x = target.minX + (window.minX - source.minX) * scaleX
        var y = target.minY + (window.minY - source.minY) * scaleY
        x = min(max(x, target.minX), target.maxX - width)
        y = min(max(y, target.minY), target.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
