import Foundation

/// Turns wheel notches into a short, easing-out series of pixel steps.
///
/// Each new notch adds to the distance still to go, so fast spinning keeps
/// flowing instead of stuttering. Every frame moves a fixed share of what's
/// left; fractions are carried over so the total always matches exactly.
nonisolated struct SmoothScroller {
    /// Share of the remaining distance covered per frame (at 120 fps ≈ 0.3 s glide).
    static let stepFraction = 0.1

    private var remainingX = 0.0
    private var remainingY = 0.0
    private var carryX = 0.0
    private var carryY = 0.0

    var isIdle: Bool { remainingX == 0 && remainingY == 0 }

    mutating func add(dx: Double, dy: Double) {
        // Changing direction mid-glide should feel instant, not fight the old motion.
        if dx * remainingX < 0 { remainingX = 0; carryX = 0 }
        if dy * remainingY < 0 { remainingY = 0; carryY = 0 }
        remainingX += dx
        remainingY += dy
    }

    /// The next whole-pixel step, or `nil` when there's nothing left to scroll.
    mutating func step() -> (dx: Int32, dy: Int32)? {
        guard !isIdle else { return nil }
        let dx = Self.advance(&remainingX, carry: &carryX)
        let dy = Self.advance(&remainingY, carry: &carryY)
        return (dx, dy)
    }

    private static func advance(_ remaining: inout Double, carry: inout Double) -> Int32 {
        guard remaining != 0 else { return 0 }
        var move = remaining * stepFraction
        // Finish off the tail instead of creeping forever.
        if abs(remaining) < 1.5 || abs(move) < 0.5 {
            move = remaining
        }
        remaining -= move
        if abs(remaining) < 0.001 { remaining = 0 }

        let exact = move + carry
        let whole = exact.rounded(.towardZero)
        carry = exact - whole
        if remaining == 0 {
            // Last step: flush the carry so nothing is lost.
            let flushed = (exact).rounded()
            carry = 0
            return Int32(flushed)
        }
        return Int32(whole)
    }
}
