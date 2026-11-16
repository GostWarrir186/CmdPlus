import AppKit
import SwiftUI

/// "Scroll Horizontally  ⓧ [ ⇧ ]" — click the box, then press a modifier key.
struct ModifierField: View {
    let role: ScrollModifierRole
    let settings: MouseSettings
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 6) {
            Text(role.title)
                .font(.callout)
            HStack(spacing: 8) {
                Button("Remove", systemImage: "xmark.circle.fill") {
                    stopRecording()
                    settings.setModifier(nil, for: role)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(settings.modifiers[role] == nil ? 0.3 : 1)
                .disabled(settings.modifiers[role] == nil)
                .help(Text("Remove"))

                Button(action: toggleRecording) {
                    Text(verbatim: label)
                        .font(.title3.weight(.medium))
                        .frame(width: 96, height: 28)
                        .foregroundStyle(isRecording ? Color.accentColor : .primary)
                        .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isRecording ? Color.accentColor : Color.primary.opacity(0.12)))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(role.title))
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if isRecording { return "…" }
        return settings.modifiers[role]?.symbol ?? "—"
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            if event.type == .keyDown {
                // Esc (or any other key) cancels.
                stopRecording()
                return nil
            }
            if let key = ScrollModifierKey(event.modifierFlags) {
                settings.setModifier(key, for: role)
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
