import AppKit
import Carbon.HIToolbox
import SwiftUI
import Testing
@testable import CmdPlus

@Suite("Window layouts")
struct WindowLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
    private let window = CGRect(x: 100, y: 100, width: 500, height: 300)

    private func frame(_ action: WindowAction, gap: CGFloat = 0) -> CGRect? {
        action.frame(in: screen, current: window, gap: gap)
    }

    @Test("Halves, quarters and thirds without gaps", arguments: [
        (WindowAction.leftHalf, CGRect(x: 0, y: 0, width: 600, height: 800)),
        (.rightHalf, CGRect(x: 600, y: 0, width: 600, height: 800)),
        (.topHalf, CGRect(x: 0, y: 400, width: 1200, height: 400)),
        (.bottomHalf, CGRect(x: 0, y: 0, width: 1200, height: 400)),
        (.topLeft, CGRect(x: 0, y: 400, width: 600, height: 400)),
        (.bottomRight, CGRect(x: 600, y: 0, width: 600, height: 400)),
        (.leftThird, CGRect(x: 0, y: 0, width: 400, height: 800)),
        (.centerThird, CGRect(x: 400, y: 0, width: 400, height: 800)),
        (.rightThird, CGRect(x: 800, y: 0, width: 400, height: 800)),
        (.leftTwoThirds, CGRect(x: 0, y: 0, width: 800, height: 800)),
        (.rightTwoThirds, CGRect(x: 400, y: 0, width: 800, height: 800)),
        (.maximize, CGRect(x: 0, y: 0, width: 1200, height: 800)),
    ])
    func layouts(action: WindowAction, expected: CGRect) {
        #expect(frame(action) == expected)
    }

    @Test("Gaps keep the same space between windows and at the edges")
    func gaps() throws {
        let left = try #require(frame(.leftHalf, gap: 10))
        let right = try #require(frame(.rightHalf, gap: 10))
        #expect(left.minX == 10)
        #expect(right.maxX == 1190)
        #expect(right.minX - left.maxX == 10)
        #expect(left.minY == 10 && left.maxY == 790)

        let thirds = try [WindowAction.leftThird, .centerThird, .rightThird].map { try #require(frame($0, gap: 10)) }
        #expect(thirds[1].minX - thirds[0].maxX == 10)
        #expect(thirds[2].minX - thirds[1].maxX == 10)
        #expect(thirds[2].maxX == 1190)
    }

    @Test("Center keeps the window's size; almost maximize stays inside the screen")
    func centerAndAlmost() throws {
        let centered = try #require(frame(.center))
        #expect(centered.size == window.size)
        #expect(centered.midX == screen.midX && centered.midY == screen.midY)
        let almost = try #require(frame(.almostMaximize))
        #expect(screen.contains(almost) && almost.width < screen.width)
    }

    @Test("Restore, Next Display and Arrange aren't single-window layouts")
    func notLayouts() {
        #expect(frame(.restore) == nil)
        #expect(frame(.nextDisplay) == nil)
        #expect(frame(.quarters) == nil)
    }

    @Test("Arrange places 2 or 4 windows side by side without overlap",
          arguments: [WindowAction.leftAndRight, .rightAndLeft, .topAndBottom, .bottomAndTop, .quarters])
    func arrange(action: WindowAction) throws {
        let layouts = try #require(action.arrangement)
        #expect(layouts.count == (action == .quarters ? 4 : 2))
        let frames = layouts.compactMap { $0.frame(in: screen, current: window, gap: 8) }
        #expect(frames.count == layouts.count)
        for (i, a) in frames.enumerated() {
            #expect(screen.contains(a))
            for b in frames[(i + 1)...] { #expect(!a.intersects(b)) }
        }
    }

    @Test("Left & Right puts the front window on the left; Right & Left on the right")
    func arrangeOrder() {
        #expect(WindowAction.leftAndRight.arrangement?.first == .leftHalf)
        #expect(WindowAction.rightAndLeft.arrangement?.first == .rightHalf)
    }

    @Test("Layouts work on a second screen with an offset origin")
    func offsetScreen() throws {
        let second = CGRect(x: 1200, y: -200, width: 1000, height: 600)
        let right = try #require(WindowAction.rightHalf.frame(in: second, current: window, gap: 0))
        #expect(right == CGRect(x: 1700, y: -200, width: 500, height: 600))
    }

    @Test("Accessibility and Cocoa coordinates convert both ways")
    func flip() {
        let cocoa = CGRect(x: 10, y: 100, width: 300, height: 200)
        let ax = ScreenCoordinates.flip(cocoa, mainScreenHeight: 900)
        #expect(ax == CGRect(x: 10, y: 600, width: 300, height: 200))
        #expect(ScreenCoordinates.flip(ax, mainScreenHeight: 900) == cocoa)
    }

    @Test("Moving to another screen keeps the relative place and size")
    func nextDisplay() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let target = CGRect(x: 1000, y: 0, width: 2000, height: 1600)
        let moved = ScreenCoordinates.move(CGRect(x: 0, y: 0, width: 500, height: 400), from: source, to: target)
        #expect(moved == CGRect(x: 1000, y: 0, width: 1000, height: 800))
    }

    @Test("Every action has an icon that exists")
    func icons() {
        for action in WindowAction.allCases {
            #expect(NSImage(systemSymbolName: action.systemImage, accessibilityDescription: nil) != nil, "\(action)")
        }
    }

    @Test("Groups list every action exactly once")
    func groups() {
        let grouped = WindowAction.groups.flatMap(\.actions)
        #expect(Set(grouped) == Set(WindowAction.allCases) && grouped.count == WindowAction.allCases.count)
    }
}

@Suite("Window shortcuts")
struct WindowShortcutTests {
    @Test("Default shortcuts are all different")
    func uniqueDefaults() {
        let combos = Array(WindowSettings.defaultShortcuts.values)
        #expect(Set(combos.map(\.displayString)).count == combos.count)
        #expect(WindowSettings.defaultShortcuts[.leftHalf]?.displayString == "⌃⌥←")
    }

    @Test("Shortcuts persist; a combo moves to the action it's assigned to last")
    func persistence() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let settings = WindowSettings(defaults: env.defaults)
        let leftHalf = settings.shortcuts[.leftHalf]
        settings.setShortcut(leftHalf, for: .maximize)
        settings.setShortcut(nil, for: .center)
        settings.gap = .large

        let reloaded = WindowSettings(defaults: env.defaults)
        #expect(reloaded.shortcuts[.maximize] == leftHalf)
        #expect(reloaded.shortcuts[.leftHalf] == nil)
        #expect(reloaded.shortcuts[.center] == nil)
        #expect(reloaded.gap == .large)

        reloaded.resetShortcuts()
        #expect(reloaded.shortcuts == WindowSettings.defaultShortcuts)
    }

    @Test("Shortcuts show up in menus the same way")
    func menuShortcuts() throws {
        let left = try #require(WindowSettings.defaultShortcuts[.leftHalf]?.swiftUIShortcut)
        #expect(left.key == .leftArrow)
        #expect(left.modifiers == [.control, .option])
        let quarters = try #require(WindowSettings.defaultShortcuts[.quarters]?.swiftUIShortcut)
        #expect(quarters.key == KeyEquivalent("q"))
        #expect(quarters.modifiers == [.control, .option, .shift])
    }

    @Test("Key combos convert to Carbon hotkey modifiers")
    func carbon() {
        let combo = KeyCombo(kVK_ANSI_K, [.maskControl, .maskAlternate, .maskCommand])
        #expect(combo.carbonModifiers == controlKey | optionKey | cmdKey)
        #expect(combo.displayString == "⌃⌥⌘K")
    }
}

@Suite("Leaving the sandbox")
struct SandboxMigrationTests {
    private func makeContainer(prefs: [String: Any]) throws -> (container: URL, support: URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        let container = root.appending(path: "Container")
        let prefsDir = container.appending(path: "Library/Preferences")
        let dataDir = container.appending(path: "Library/Application Support/CmdPlus/ClipboardHistory")
        try FileManager.default.createDirectory(at: prefsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        (prefs as NSDictionary).write(to: prefsDir.appending(path: "com.azam.CmdPlus.plist"), atomically: true)
        try Data("[]".utf8).write(to: dataDir.appending(path: "history.json"))
        return (container, root.appending(path: "Support"))
    }

    @Test("Settings and history are copied once, without overwriting anything")
    func migrates() throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let paths = try makeContainer(prefs: ["clipboard.historyLimit": 42, "appearance.theme": "dark"])
        env.defaults.set("light", forKey: "appearance.theme") // already set here — keep it

        SandboxMigration.runIfNeeded(defaults: env.defaults, container: paths.container, applicationSupport: paths.support)

        #expect(env.defaults.integer(forKey: "clipboard.historyLimit") == 42)
        #expect(env.defaults.string(forKey: "appearance.theme") == "light")
        #expect(FileManager.default.fileExists(atPath: paths.support.appending(path: "CmdPlus/ClipboardHistory/history.json").path))
        #expect(env.defaults.bool(forKey: SandboxMigration.doneKey))

        // Second run does nothing.
        env.defaults.set(10, forKey: "clipboard.historyLimit")
        SandboxMigration.runIfNeeded(defaults: env.defaults, container: paths.container, applicationSupport: paths.support)
        #expect(env.defaults.integer(forKey: "clipboard.historyLimit") == 10)
    }

    @Test("No old container — nothing to do")
    func noContainer() {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        let missing = FileManager.default.temporaryDirectory.appending(path: "none-\(UUID().uuidString)")
        SandboxMigration.runIfNeeded(defaults: env.defaults, container: missing, applicationSupport: missing)
        #expect(env.defaults.bool(forKey: SandboxMigration.doneKey))
    }
}
