import SwiftUI

struct MouseSettingsView: View {
    let module: MouseModule
    /// Row waiting for a recorded shortcut.
    @State private var recordingFor: RecordingTarget?

    var body: some View {
        @Bindable var settings = module.settings

        ModuleSettingsForm(descriptor: MouseModule.descriptor) {
            if !module.hasAccess {
                Section {
                    LabeledContent {
                        Button("Allow Access…") { module.requestAccess() }
                    } label: {
                        Label("Accessibility permission is needed", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("CmdPlus needs the Accessibility permission to change scrolling and to react to mouse buttons. Nothing is recorded or sent anywhere.")
                }
            }

            Section {
                Toggle("Smooth Scrolling", isOn: $settings.smoothScrolling)
                LabeledContent("Scrolling Speed") {
                    HStack(spacing: 10) {
                        Image(systemName: "tortoise")
                            .foregroundStyle(.secondary)
                        Slider(value: $settings.scrollSpeed, in: MouseSettings.speedRange, step: 0.25)
                            .frame(width: 180)
                        Image(systemName: "hare")
                            .foregroundStyle(.secondary)
                        Text(verbatim: settings.scrollSpeed.formatted(.number.precision(.fractionLength(2))) + "×")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("Reverse Vertical Scrolling", isOn: $settings.reverseVertical)
                Toggle("Reverse Horizontal Scrolling", isOn: $settings.reverseHorizontal)
            } header: {
                Text("Scrolling")
            } footer: {
                Text("Only mice with a scroll wheel are affected. Trackpads and Magic Mouse keep the behavior set in System Settings.")
            }

            Section {
                ButtonCaptureField(settings: settings)
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            } header: {
                Text("Buttons")
            } footer: {
                Text("Move the pointer into the + field and press a mouse button to assign an action to it. Double-press to assign a double click.")
            }

            ForEach(buttonsInUse(settings), id: \.self) { button in
                Section {
                    ForEach(settings.bindings(forButton: button)) { binding in
                        BindingRow(binding: binding, settings: settings) {
                            recordingFor = RecordingTarget(id: binding.id)
                        }
                    }
                } header: {
                    Text(ButtonBinding.name(of: button))
                }
            }
        }
        .sheet(item: $recordingFor) { target in
            ShortcutRecorder { recorded in
                update(target.id) { row in
                    if let recorded {
                        row.shortcut = recorded
                    } else if row.shortcut == nil {
                        // Cancelled with nothing recorded — don't leave an empty choice.
                        row.action = .systemDefault
                    }
                }
                recordingFor = nil
            }
        }
        // Permission is granted in System Settings, so re-check when the user comes back.
        .onAppear { module.refreshAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            module.refreshAccess()
        }
    }

    /// Buttons with rows, in the order they were first added.
    private func buttonsInUse(_ settings: MouseSettings) -> [Int64] {
        var seen: [Int64] = []
        for binding in settings.bindings where !seen.contains(binding.button) {
            seen.append(binding.button)
        }
        return seen
    }

    private func update(_ id: UUID, _ change: (inout ButtonBinding) -> Void) {
        guard let index = module.settings.bindings.firstIndex(where: { $0.id == id }) else { return }
        change(&module.settings.bindings[index])
    }
}

private struct RecordingTarget: Identifiable {
    let id: UUID
}

/// "− Click            [Mission Control ⌃]"
private struct BindingRow: View {
    let binding: ButtonBinding
    let settings: MouseSettings
    let recordShortcut: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button("Remove", systemImage: "minus.circle.fill") {
                settings.removeBinding(binding.id)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(Text("Remove"))

            Text(binding.trigger.title)

            Spacer()

            Picker(selection: actionBinding) {
                ForEach(Array(MouseButtonAction.groups.enumerated()), id: \.offset) { index, group in
                    if index > 0 { Divider() }
                    ForEach(group) { action in
                        actionLabel(action).tag(action)
                    }
                }
            } label: {
                Text(binding.trigger.title)
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    @ViewBuilder
    private func actionLabel(_ action: MouseButtonAction) -> some View {
        if action == .keyboardShortcut, let shortcut = binding.shortcut {
            Text(verbatim: shortcut.display)
        } else {
            Text(action.title)
        }
    }

    private var actionBinding: Binding<MouseButtonAction> {
        Binding(
            get: { binding.action },
            set: { newValue in
                guard let index = settings.bindings.firstIndex(where: { $0.id == binding.id }) else { return }
                settings.bindings[index].action = newValue
                if newValue == .keyboardShortcut { recordShortcut() }
            }
        )
    }
}
