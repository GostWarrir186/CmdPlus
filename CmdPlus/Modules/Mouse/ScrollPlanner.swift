import CoreGraphics

/// Works out what one wheel notch should do. Pure logic, so it's testable.
nonisolated enum ScrollPlanner {
    /// Pixels one line scrolls at medium speed when smoothing.
    static let pixelsPerLine = 40.0
    static let swiftMultiplier = 3.0
    static let preciseMultiplier = 0.25

    enum Plan: Equatable {
        /// Send ⌘+ (true) or ⌘− (false) instead of scrolling.
        case zoom(zoomIn: Bool)
        /// Scroll by these many lines on each axis; strip `removeFlags` so apps
        /// don't also react to the modifier the user is holding.
        case scroll(vertical: Double, horizontal: Double, removeFlags: CGEventFlags)
    }

    /// - Parameters:
    ///   - lines: whole and accelerated line deltas of the notch, per axis.
    struct Input {
        var wholeVertical: Double
        var acceleratedVertical: Double
        var wholeHorizontal: Double
        var acceleratedHorizontal: Double
        var flags: CGEventFlags
    }

    static func plan(_ input: Input, settings: MouseSettings) -> Plan {
        let roles = settings.activeRoles(for: input.flags)
        let usedFlags = roles.reduce(CGEventFlags()) { $0.union(settings.modifiers[$1]?.eventFlag ?? []) }

        var vertical = lines(whole: input.wholeVertical, accelerated: input.acceleratedVertical, precise: settings.precision)
        var horizontal = lines(whole: input.wholeHorizontal, accelerated: input.acceleratedHorizontal, precise: settings.precision)

        if roles.contains(.zoom) {
            // Zoom follows the wheel as the user sees it (after reversing).
            let direction = vertical * (settings.reverseVertical ? -1 : 1)
            return .zoom(zoomIn: direction > 0)
        }

        var multiplier = settings.speed.multiplier
        if roles.contains(.swift) { multiplier *= swiftMultiplier }
        if roles.contains(.precise) { multiplier *= preciseMultiplier }

        vertical *= multiplier * (settings.reverseVertical ? -1 : 1)
        horizontal *= multiplier * (settings.reverseHorizontal ? -1 : 1)

        if roles.contains(.horizontal) {
            horizontal += vertical
            vertical = 0
        }
        return .scroll(vertical: vertical, horizontal: horizontal, removeFlags: usedFlags)
    }

    /// A slow notch reports one whole line but only ~0.1 accelerated. Normally a
    /// notch scrolls at least a line; with Precision, slow notches stay small.
    static func lines(whole: Double, accelerated: Double, precise: Bool) -> Double {
        if precise && abs(accelerated) < abs(whole) { return accelerated }
        return abs(accelerated) > abs(whole) ? accelerated : whole
    }
}
