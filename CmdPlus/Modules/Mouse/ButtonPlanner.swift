import Foundation

/// Decides what to do when a mouse button goes down. Pure logic, so it's testable.
nonisolated enum ButtonPlanner {
    enum Plan: Equatable {
        /// Not ours — let the app see the click.
        case passThrough
        /// Run this binding right away.
        case perform(ButtonBinding)
        /// There's also a double-click binding: wait a moment before running this.
        case waitForDoubleClick(ButtonBinding)
    }

    /// - Parameter clickCount: 1 for a single press, 2 for the second press of a double click.
    static func plan(button: Int64, clickCount: Int64, bindings: [ButtonBinding]) -> Plan {
        let forButton = bindings.filter { $0.button == button && $0.action != .systemDefault }
        let click = forButton.first { $0.trigger == .click }
        let double = forButton.first { $0.trigger == .doubleClick }

        if clickCount >= 2, let double { return .perform(double) }
        switch (click, double) {
        case (nil, nil): return .passThrough
        case (let click?, nil): return .perform(click)
        // Only a double click is assigned: single clicks keep their usual job.
        case (nil, _?): return .passThrough
        case (let click?, _?): return .waitForDoubleClick(click)
        }
    }
}
