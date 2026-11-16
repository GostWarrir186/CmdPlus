import Foundation

/// Turns wheel notches into a short, easing-out series of pixel steps.
///
/// Each new notch adds to the distance still to go, so fast spinning keeps
/// flowing instead of stuttering. Every frame moves a fixed share of what's
/// left; fractions are carried over so the total always matches exactly.
/// Steps also carry trackpad-style phases: began, changed…, ended.
nonisolated struct SmoothScroller {
    enum Phase: Equatable { case began, changed, ended }

    struct Step: Equatable {
        let dx: Int32
        let dy: Int32
        let phase: Phase
    }

    var stepFraction: Double

    private var remainingX = 0.0
    private var remainingY = 0.0
    private var carryX = 0.0
    private var carryY = 0.0
    private var inGesture = false

    init(stepFraction: Double = 0.14) {
        self.stepFraction = stepFraction
    }

    /// No distance left and no gesture to close.
    var isIdle: Bool { !hasDistance && !inGesture }

    private var hasDistance: Bool { remainingX != 0 || remainingY != 0 }

    mutating func add(dx: Double, dy: Double) {
        // Changing direction mid-glide should feel instant, not fight the old motion.
        if dx * remainingX < 0 { remainingX = 0; carryX = 0 }
        if dy * remainingY < 0 { remainingY = 0; carryY = 0 }
        remainingX += dx
        remainingY += dy
    }

    /// The next whole-pixel step, then one final zero-length `.ended` step,
    /// then `nil` until more distance is added.
    mutating func step() -> Step? {
        guard hasDistance else {
            guard inGesture else { return nil }
            inGesture = false
            return Step(dx: 0, dy: 0, phase: .ended)
        }
        let phase: Phase = inGesture ? .changed : .began
        inGesture = true
        let dx = advance(&remainingX, carry: &carryX)
        let dy = advance(&remainingY, carry: &carryY)
        return Step(dx: dx, dy: dy, phase: phase)
    }

    private func advance(_ remaining: inout Double, carry: inout Double) -> Int32 {
        guard remaining != 0 else { return 0 }
        var move = remaining * stepFraction
        // Finish off the tail instead of creeping forever.
        if abs(remaining) < 1.5 || abs(move) < 0.5 {
            move = remaining
        }
        remaining -= move
        if abs(remaining) < 0.001 { remaining = 0 }

        let exact = move + carry
        if remaining == 0 {
            // Last step: flush the carry so nothing is lost.
            carry = 0
            return Int32(exact.rounded())
        }
        let whole = exact.rounded(.towardZero)
        carry = exact - whole
        return Int32(whole)
    }
}
