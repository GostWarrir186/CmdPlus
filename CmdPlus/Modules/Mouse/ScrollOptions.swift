import CoreGraphics
import SwiftUI

nonisolated enum ScrollSmoothness: String, CaseIterable, Identifiable, Sendable {
    case off, regular, high

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .off: "Off"
        case .regular: "Regular"
        case .high: "High"
        }
    }

    /// Share of the remaining distance covered per frame at 120 fps.
    /// Regular ≈ 0.2 s glide, High ≈ 0.4 s.
    var stepFraction: Double? {
        switch self {
        case .off: nil
        case .regular: 0.14
        case .high: 0.07
        }
    }
}

nonisolated enum ScrollSpeed: String, CaseIterable, Identifiable, Sendable {
    case low, medium, high

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var multiplier: Double {
        switch self {
        case .low: 0.6
        case .medium: 1
        case .high: 1.8
        }
    }

    /// Nearest preset for an old slider value (migration).
    static func nearest(to value: Double) -> ScrollSpeed {
        allCases.min { abs($0.multiplier - value) < abs($1.multiplier - value) } ?? .medium
    }
}

/// A modifier key that changes what the wheel does while it's held.
nonisolated enum ScrollModifierKey: String, CaseIterable, Identifiable, Sendable {
    case shift, control, option, command

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .shift: "⇧"
        case .control: "⌃"
        case .option: "⌥"
        case .command: "⌘"
        }
    }

    var eventFlag: CGEventFlags {
        switch self {
        case .shift: .maskShift
        case .control: .maskControl
        case .option: .maskAlternate
        case .command: .maskCommand
        }
    }

    init?(_ flags: NSEvent.ModifierFlags) {
        switch flags.intersection([.shift, .control, .option, .command]) {
        case .shift: self = .shift
        case .control: self = .control
        case .option: self = .option
        case .command: self = .command
        default: return nil
        }
    }
}

/// What a held modifier does to scrolling.
nonisolated enum ScrollModifierRole: String, CaseIterable, Identifiable, Sendable {
    case horizontal, zoom, swift, precise

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .horizontal: "Scroll Horizontally"
        case .zoom: "Zoom In or Out"
        case .swift: "Scroll Swiftly"
        case .precise: "Scroll Precisely"
        }
    }

    var defaultKey: ScrollModifierKey {
        switch self {
        case .horizontal: .shift
        case .zoom: .command
        case .swift: .control
        case .precise: .option
        }
    }
}
