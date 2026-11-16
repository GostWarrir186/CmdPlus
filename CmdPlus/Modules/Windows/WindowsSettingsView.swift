import SwiftUI

struct WindowsSettingsView: View {
    let module: WindowsModule
    @State private var recordingFor: WindowAction?

    var body: some View {
        @Bindable var settings = module.settings

        ModuleSettingsForm(descriptor: WindowsModule.descriptor) {
            if !module.hasAccess {
                Section {
                    LabeledContent {
                        Button("Allow Access…") { module.requestAccess() }
                    } label: {
                        Label("Accessibility permission is needed", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("CmdPlus needs the Accessibility permission to move and resize other apps' windows.")
                }
            }

            Section {
                Label {
                    Text("Click the window you want to move, then press its shortcut — for example ⌃⌥← puts it on the left half.")
                } icon: {
                    Image(systemName: "keyboard")
                }
                Label {
                    Text("Or click the CmdPlus icon in the menu bar and pick a layout in the Windows tile.")
                } icon: {
                    Image(systemName: "menubar.rectangle")
                }
                Label {
                    Text("Arrange lays out the front window and the ones right behind it at once.")
                } icon: {
                    Image(systemName: "rectangle.split.2x2")
                }
            } header: {
                Text("How to Use")
            }
            .foregroundStyle(.secondary)

            Section {
                Picker("Gaps Between Windows", selection: $settings.gap) {
                    ForEach(WindowGap.allCases) { Text($0.title).tag($0) }
                }
            } footer: {
                Text("Dragging a window to the edge of the screen to tile it is built into macOS.")
            }

            ForEach(Array(WindowAction.groups.enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group.actions) { action in
                        ShortcutRow(action: action, module: module) {
                            recordingFor = action
                        }
                    }
                } header: {
                    Text(group.title)
                }
            }

            Section {
                Button("Restore Default Shortcuts") { settings.resetShortcuts() }
            }
        }
        .sheet(item: $recordingFor) { action in
            ShortcutRecorder { recorded in
                if let recorded { module.settings.setShortcut(recorded.combo, for: action) }
                recordingFor = nil
            }
            .onAppear { module.isRecordingShortcut = true }
            .onDisappear { module.isRecordingShortcut = false }
        }
        // Permission is granted in System Settings, so re-check when the user comes back.
        .onAppear { module.refreshAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            module.refreshAccess()
        }
    }
}

/// "▐ Left Half          ⓧ [ ⌃⌥← ]"
private struct ShortcutRow: View {
    let action: WindowAction
    let module: WindowsModule
    let record: () -> Void

    var body: some View {
        let combo = module.settings.shortcuts[action]

        HStack(spacing: 10) {
            Image(systemName: action.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(action.title)
            if module.conflicts.contains(action) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(Text("Another app already uses this shortcut."))
            }
            Spacer()
            if combo != nil {
                Button("Remove", systemImage: "xmark.circle.fill") {
                    module.settings.setShortcut(nil, for: action)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(Text("Remove"))
            }
            Button(action: record) {
                Text(verbatim: combo?.displayString ?? String(localized: "Record Shortcut"))
                    .font(combo == nil ? .callout : .body.weight(.medium))
                    .foregroundStyle(combo == nil ? .secondary : .primary)
                    .frame(minWidth: 96)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}

