import AppKit
import SwiftUI
import Testing
@testable import CmdPlus

/// Renders the screenshots used in README.md from demo data, so no real
/// clipboard history ever ends up in the repo.
///
/// Skipped during normal test runs. To regenerate:
///
///     TEST_RUNNER_CMDPLUS_SCREENSHOTS=1 xcodebuild test -project CmdPlus.xcodeproj \
///       -scheme CmdPlus -destination 'platform=macOS' -testLanguage en \
///       -only-testing:CmdPlusTests/ReadmeScreenshots | grep '^SCREENSHOT '
///
/// The test host is sandboxed, so images are printed as base64 lines
/// (`SCREENSHOT <name> <base64>`) instead of being written into the repo directly.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CMDPLUS_SCREENSHOTS"] != nil))
struct ReadmeScreenshots {
    @Test func render() async throws {
        let env = TestEnvironment()
        defer { env.cleanUp() }
        try DemoData.write(to: env.directory)

        let settings = env.makeSettings(limit: 50)
        let module = ClipboardHistoryModule(settings: settings, directory: env.directory)
        await module.store.load()

        for scheme in [ColorScheme.dark, .light] {
            let model = HistoryViewModel(module: module)
            model.selectedID = module.store.items[1].id
            let window = HistoryView(model: model)
                .clipShape(.rect(cornerRadius: Design.History.windowRadius))
            try await snapshot(
                Showcase(scheme: scheme) { window },
                name: "history-\(scheme == .dark ? "dark" : "light")",
                scheme: scheme
            )
        }

        // Just the module page: the sidebar's system material doesn't render offscreen.
        try await snapshot(
            Showcase(scheme: .dark) {
                ClipboardSettingsView(module: module)
                    .environment(ModuleManager.shared)
                    .frame(width: 640, height: 640)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(.rect(cornerRadius: 16))
            },
            name: "settings",
            scheme: .dark
        )

        try await snapshot(AppLogo(), name: "logo", scheme: .light)
    }

    /// The title bar renders as a black band over the top of the content, so we add
    /// this much clear space on top (which also renders black) and crop both off.
    private static let titleBarHeight: CGFloat = 32

    private func snapshot(_ view: some View, name: String, scheme: ColorScheme) async throws {
        let padded = VStack(spacing: 0) {
            Color.clear.frame(height: Self.titleBarHeight)
            view
        }
        // Render controls as in a focused window, whatever app has focus right now.
        let host = NSHostingView(rootView: padded
            .environment(\.colorScheme, scheme)
            .environment(\.controlActiveState, .key))
        host.frame.size = host.fittingSize
        // A non-activating panel becomes the key window without stealing focus from
        // whatever app is in front, so switches and buttons render in their active colors.
        let window = NSPanel(contentRect: host.frame, styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
                             backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        // Give thumbnails time to decode.
        try await Task.sleep(for: .seconds(2))
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let full = try #require(rep.cgImage)
        let scale = CGFloat(full.height) / host.bounds.height
        let band = Int(Self.titleBarHeight * 2 * scale)
        let cropped = try #require(full.cropping(to: CGRect(x: 0, y: band, width: full.width, height: full.height - band)))
        let png = try #require(NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:]))
        print("SCREENSHOT \(name) \(png.base64EncodedString())")
        window.close()
    }
}

/// A window on a soft gradient "desktop" with a drop shadow.
private struct Showcase<Content: View>: View {
    let scheme: ColorScheme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
            .padding(.horizontal, 70)
            .padding(.vertical, 60)
            .background {
                if scheme == .dark {
                    LinearGradient(colors: [Color(red: 0.16, green: 0.12, blue: 0.38), Color(red: 0.02, green: 0.30, blue: 0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                } else {
                    LinearGradient(colors: [Color(red: 0.98, green: 0.80, blue: 0.70), Color(red: 0.62, green: 0.78, blue: 1.0)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
    }
}

/// App mark for the README header: ⌘ on a blue squircle.
private struct AppLogo: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 58, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.55, blue: 1.0), Color(red: 0.36, green: 0.25, blue: 0.95)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                Image(systemName: "command")
                    .font(.system(size: 120, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "plus")
                    .font(.system(size: 54, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(26)
            }
            .frame(width: 256, height: 256)
            .padding(20)
    }
}

/// Believable sample history.
private enum DemoData {
    static func write(to directory: URL) throws {
        let images = directory.appending(path: "images", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let files = directory.appending(path: "files", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)

        let sunset = try makeImage(named: "sunset", in: images, colors: [.orange, .pink, .purple])
        let ocean = try makeImage(named: "ocean", in: images, colors: [.teal, .blue, .indigo])
        let report = files.appending(path: "Q4 Report.pdf")
        try Data().write(to: report)

        func ago(_ minutes: Double) -> Date { .now.addingTimeInterval(-minutes * 60) }
        let items: [ClipboardItem] = [
            ClipboardItem(kind: .text, createdAt: ago(0.2),
                          text: "Design review moved to Thursday at 3 PM — bring the new onboarding flow.",
                          sourceAppName: "Notes"),
            ClipboardItem(kind: .image, createdAt: ago(1), imageFile: sunset, imageWidth: 1600, imageHeight: 1000,
                          sourceAppName: "Photos"),
            ClipboardItem(kind: .text, createdAt: ago(3),
                          text: "https://developer.apple.com/documentation/swiftui",
                          sourceAppName: "Safari"),
            ClipboardItem(kind: .text, createdAt: ago(6),
                          text: "let greeting = \"Hello, CmdPlus!\"\nprint(greeting)",
                          sourceAppName: "Xcode"),
            ClipboardItem(kind: .files, createdAt: ago(12), filePaths: [report.path],
                          sourceAppName: "Finder"),
            ClipboardItem(kind: .text, createdAt: ago(18),
                          text: "#0A84FF",
                          sourceAppName: "Figma"),
            ClipboardItem(kind: .image, createdAt: ago(25), imageFile: ocean, imageWidth: 1600, imageHeight: 1000,
                          sourceAppName: "Safari"),
            ClipboardItem(kind: .text, createdAt: ago(40),
                          text: "1 Infinite Loop, Cupertino, CA 95014",
                          isPinned: true, sourceAppName: "Maps"),
            ClipboardItem(kind: .text, createdAt: ago(90),
                          text: "Thanks for the quick turnaround! Shipping it tonight 🚀",
                          sourceAppName: "Messages"),
        ]
        try JSONEncoder().encode(items).write(to: directory.appending(path: "history.json"))
    }

    @MainActor
    private static func makeImage(named name: String, in folder: URL, colors: [Color]) throws -> String {
        let art = ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.white.opacity(0.35)).frame(width: 360).offset(x: 360, y: -160).blur(radius: 6)
            Ellipse().fill(.black.opacity(0.18)).frame(width: 2200, height: 600).offset(y: 520)
        }
        .frame(width: 1600, height: 1000)
        let renderer = ImageRenderer(content: art)
        let cgImage = try #require(renderer.cgImage)
        let png = try #require(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
        let file = "\(name).png"
        try png.write(to: folder.appending(path: file))
        return file
    }
}
