import SwiftUI

struct ClipboardSettingsView: View {
    let module: ClipboardHistoryModule
    @State private var isConfirmingClear = false

    var body: some View {
        @Bindable var settings = module.settings
        let store = module.store

        ModuleSettingsForm(descriptor: ClipboardHistoryModule.descriptor) {
            Section("History") {
                LabeledContent("Keyboard Shortcut") {
                    Text(verbatim: "⇧⌘V")
                }
                if module.hotKeyFailed {
                    Label("⇧⌘V is already used by another app.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                HistoryLimitPicker(settings: settings, store: store)
            }

            Section {
                Toggle("Paste Directly", isOn: $settings.pasteDirectly)
                if settings.pasteDirectly {
                    if module.hasPasteAccess {
                        Label("Access granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        LabeledContent {
                            Button("Allow Access…") { module.requestPasteAccess() }
                        } label: {
                            Label("Accessibility permission is needed", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            } header: {
                Text("Pasting")
            } footer: {
                Text("When you choose an item, CmdPlus pastes it into the app you were working in by pressing ⌘V for you. This needs the Accessibility permission. Without it, items are only copied. Press ⌥↩ to copy without pasting.")
            }

            Section("Storage") {
                LabeledContent("Saved Items") {
                    Text("\(store.unpinnedCount) of \(settings.historyLimit)")
                }
                LabeledContent("Pinned Items") {
                    Text("\(store.items.count - store.unpinnedCount)")
                }
                HStack {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.directory])
                    }
                    Spacer()
                    Button("Clear History…", role: .destructive) {
                        isConfirmingClear = true
                    }
                }
            }
        }
        .confirmationDialog("Clear clipboard history?", isPresented: $isConfirmingClear) {
            Button("Clear History", role: .destructive) {
                store.clearUnpinned()
            }
        } message: {
            Text("Pinned items will be kept.")
        }
        // Permission is granted in System Settings, so re-check when the user comes back.
        .onAppear { module.refreshPasteAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            module.refreshPasteAccess()
        }
    }
}

/// Limit picker: presets apply immediately, a custom number only on Return
/// or Apply — otherwise typing "100" would wipe history right after the "1".
private struct HistoryLimitPicker: View {
    @Bindable var settings: ClipboardSettings
    let store: ClipboardStore

    /// `nil` means "Custom…".
    @State private var choice: Int?
    @State private var customValue = ClipboardSettings.defaultLimit

    var body: some View {
        Picker("History Limit", selection: $choice) {
            ForEach(ClipboardSettings.limitPresets, id: \.self) { preset in
                Text("\(preset) items").tag(Int?.some(preset))
            }
            Divider()
            Text("Custom…").tag(Int?.none)
        }
        .onAppear(perform: syncFromSettings)
        .onChange(of: choice) { _, newChoice in
            if let newChoice {
                apply(newChoice)
            } else {
                customValue = settings.historyLimit
            }
        }

        if choice == nil {
            LabeledContent("Number of Items") {
                HStack {
                    TextField("Number of Items", value: $customValue, format: .number)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onSubmit { apply(customValue) }
                    Button("Apply") { apply(customValue) }
                        .disabled(customValue == settings.historyLimit)
                }
            }
        }

        Text("From 1 to 500 items. Pinned items don't count toward the limit. When you lower the limit, the oldest unpinned items are deleted right away.")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private func syncFromSettings() {
        let limit = settings.historyLimit
        choice = ClipboardSettings.limitPresets.contains(limit) ? limit : nil
        customValue = limit
    }

    private func apply(_ value: Int) {
        let limit = value.clamped(to: ClipboardSettings.limitRange)
        customValue = limit
        guard limit != settings.historyLimit else { return }
        settings.historyLimit = limit
        store.applyLimit()
    }
}
