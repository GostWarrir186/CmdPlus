import SwiftUI

struct GeneralSettingsView: View {
    @State private var launchAtLogin = LaunchAtLogin()
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open at Login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                Text("CmdPlus starts silently: only the menu bar icon appears, no windows.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if launchAtLogin.requiresApproval {
                    LabeledContent("Allow CmdPlus in System Settings → Login Items.") {
                        Button("Open Login Items") {
                            launchAtLogin.openSystemSettings()
                        }
                    }
                }

                if let error = launchAtLogin.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                Text("All data stays on this Mac. CmdPlus does not use any servers.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text("General"))
        .onAppear { launchAtLogin.refresh() }
        .onChange(of: theme) { _, newTheme in newTheme.apply() }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
