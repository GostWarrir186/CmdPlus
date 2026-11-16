import SwiftUI

struct MouseSettingsView: View {
    let module: MouseModule

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
                    Text("CmdPlus needs the Accessibility permission to change scrolling direction and to react to mouse buttons. Nothing is recorded or sent anywhere.")
                }
            }

            Section {
                Toggle("Reverse Vertical Scrolling", isOn: $settings.reverseVertical)
                Toggle("Reverse Horizontal Scrolling", isOn: $settings.reverseHorizontal)
            } header: {
                Text("Scrolling")
            } footer: {
                Text("Only mice with a scroll wheel are affected. Trackpads and Magic Mouse keep the direction set in System Settings.")
            }

            Section {
                ButtonActionPicker(title: "Back Button", selection: $settings.backButton)
                ButtonActionPicker(title: "Forward Button", selection: $settings.forwardButton)
            } header: {
                Text("Side Buttons")
            } footer: {
                Text("The two extra buttons on the side of many mice. Choose “System Default” to leave a button as it is.")
            }
        }
        // Permission is granted in System Settings, so re-check when the user comes back.
        .onAppear { module.refreshAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            module.refreshAccess()
        }
    }
}

private struct ButtonActionPicker: View {
    let title: LocalizedStringResource
    @Binding var selection: MouseButtonAction

    var body: some View {
        Picker(selection: $selection) {
            ForEach(Array(MouseButtonAction.groups.enumerated()), id: \.offset) { index, group in
                if index > 0 { Divider() }
                ForEach(group) { action in
                    Text(action.title).tag(action)
                }
            }
        } label: {
            Text(title)
        }
    }
}
