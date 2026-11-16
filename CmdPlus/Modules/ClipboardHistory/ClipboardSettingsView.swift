import SwiftUI

/// Параметры модуля «История буфера» в окне настроек.
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

            Section {
                Toggle("Save Passwords and Codes", isOn: $settings.captureSecrets)
                Picker("Keep Passwords For", selection: $settings.secretRetention) {
                    ForEach(SecretRetention.allCases) { retention in
                        Text(retention.title).tag(retention)
                    }
                }
                .disabled(!settings.captureSecrets)

                if let error = store.vaultError {
                    Label {
                        Text("Couldn't save to Keychain: \(error)")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    .foregroundStyle(.orange)
                }
            } header: {
                Text("Passwords and Codes")
            } footer: {
                Text("Passwords copied from password managers are encrypted in the Keychain of this Mac only. They are never synced to iCloud and never included in settings export. In the list they are shown as dots and revealed with Touch ID. Pinned passwords are not deleted automatically.")
            }
        }
        .confirmationDialog("Clear clipboard history?", isPresented: $isConfirmingClear) {
            Button("Clear History", role: .destructive) {
                store.clearUnpinned()
            }
        } message: {
            Text("Pinned items will be kept.")
        }
        .onChange(of: settings.secretRetention) {
            store.purgeExpiredSecrets()
        }
    }
}

/// Выбор лимита: готовые варианты или своё число.
///
/// Готовый вариант применяется сразу. Своё число — только по Enter или кнопке
/// «Применить», иначе при наборе «100» после первой «1» удалилась бы почти вся история.
private struct HistoryLimitPicker: View {
    @Bindable var settings: ClipboardSettings
    let store: ClipboardStore

    /// `nil` в списке означает «Своё значение…».
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
