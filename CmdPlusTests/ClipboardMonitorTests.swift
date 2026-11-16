import AppKit
import Testing
@testable import CmdPlus

/// Uses a private, uniquely named pasteboard — the real clipboard is never touched.
@Suite("Clipboard capture")
struct ClipboardMonitorTests {
    private func withPasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
        let pasteboard = NSPasteboard(name: .init("CmdPlusTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        try body(pasteboard)
    }

    @Test("Plain text is captured")
    func capturesText() {
        withPasteboard { pasteboard in
            pasteboard.setString("hello", forType: .string)
            guard case .text(let text) = ClipboardMonitor.readContent(of: pasteboard) else {
                Issue.record("expected text"); return
            }
            #expect(text == "hello")
        }
    }

    @Test("Passwords marked by password managers are never captured", arguments: [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "com.agilebits.onepassword",
    ])
    func skipsSecrets(marker: String) {
        withPasteboard { pasteboard in
            let type = NSPasteboard.PasteboardType(marker)
            pasteboard.declareTypes([.string, type], owner: nil)
            pasteboard.setString("hunter2", forType: .string)
            pasteboard.setData(Data(), forType: type)
            #expect(ClipboardMonitor.readContent(of: pasteboard) == nil)
        }
    }

    @Test("Whitespace-only text is ignored")
    func skipsBlankText() {
        withPasteboard { pasteboard in
            pasteboard.setString("  \n ", forType: .string)
            #expect(ClipboardMonitor.readContent(of: pasteboard) == nil)
        }
    }
}
