import SwiftUI

/// Settings window in the style of System Settings.
///
/// The sidebar has a fixed width and can't be collapsed, which is why this isn't
/// a `NavigationSplitView` (its divider is always draggable).
struct SettingsView: View {
    @Environment(ModuleManager.self) private var modules
    @State private var selection: SettingsPane? = .general

    static let sidebarWidth: CGFloat = 270

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: Self.sidebarWidth)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 500)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            SidebarRow(title: "General", systemImage: "gearshape.fill", tint: .gray)
                .tag(SettingsPane.general)

            Section("Modules") {
                ForEach(modules.descriptors) { descriptor in
                    // The module's on/off switch lives in its page header, not the sidebar.
                    SidebarRow(title: descriptor.title, systemImage: descriptor.systemImage, tint: descriptor.tint)
                        .tag(SettingsPane.module(descriptor.id))
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .module(let id):
            if let descriptor = modules.descriptors.first(where: { $0.id == id }) {
                ModuleSettingsDetail(descriptor: descriptor)
            }
        case .general, nil:
            GeneralSettingsView()
        }
    }
}

/// Sidebar row like System Settings: long titles wrap, and the icon lines up
/// with the first line. Icon size follows the system sidebar size setting.
private struct SidebarRow: View {
    @Environment(\.sidebarRowSize) private var rowSize
    let title: LocalizedStringResource
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TintedIcon(systemImage: systemImage, tint: tint, size: iconSize)
                // Center the icon on the first line of text, just above the baseline.
                .alignmentGuide(.firstTextBaseline) { d in
                    d[VerticalAlignment.center] + iconSize * 0.22
                }
            Text(title)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var iconSize: CGFloat {
        switch rowSize {
        case .small: 16
        case .large: 24
        default: 20
        }
    }
}

enum SettingsPane: Hashable {
    case general
    case module(String)
}

/// A module's page: its own settings when enabled, a hint when it's off
/// (a disabled module isn't even created).
private struct ModuleSettingsDetail: View {
    @Environment(ModuleManager.self) private var modules
    let descriptor: ModuleDescriptor

    var body: some View {
        if let module = modules.module(for: descriptor.id) {
            module.makeSettingsView()
        } else {
            ModuleSettingsForm(descriptor: descriptor) {
                Section {
                    Text("Turn on the module to change its settings.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Shared wrapper for module pages: header with icon, summary and switch,
/// then the module's own sections.
struct ModuleSettingsForm<Content: View>: View {
    @Environment(ModuleManager.self) private var modules
    let descriptor: ModuleDescriptor
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    TintedIcon(systemImage: descriptor.systemImage, tint: descriptor.tint, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(descriptor.title)
                            .font(.title2.bold())
                        Text(descriptor.summary)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(isOn: modules.binding(for: descriptor.id)) {
                        Text(descriptor.title)
                    }
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                .padding(.vertical, 4)
            }

            content
        }
        .formStyle(.grouped)
        .navigationTitle(Text(descriptor.title))
    }
}
