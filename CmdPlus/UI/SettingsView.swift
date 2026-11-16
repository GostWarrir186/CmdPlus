import SwiftUI

/// Окно настроек в стиле Системных настроек:
/// слева «Основные» и список модулей с тумблерами, справа — параметры выбранного пункта.
struct SettingsView: View {
    @Environment(ModuleManager.self) private var modules
    @State private var selection: SettingsPane? = .general
    /// Боковая панель всегда видна: кнопку скрытия убрали, а перетаскиванием
    /// края её тоже нельзя схлопнуть — иначе вернуть её было бы нечем.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                NavigationLink(value: SettingsPane.general) {
                    SidebarRow(title: "General", systemImage: "gearshape.fill", tint: .gray)
                }

                Section("Modules") {
                    ForEach(modules.descriptors) { descriptor in
                        NavigationLink(value: SettingsPane.module(descriptor.id)) {
                            SidebarRow(
                                title: descriptor.title,
                                systemImage: descriptor.systemImage,
                                tint: descriptor.tint
                            ) {
                                Toggle(isOn: modules.binding(for: descriptor.id)) {
                                    Text(descriptor.title)
                                }
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 290, max: 360)
            // Как в Системных настройках: боковую панель нельзя скрыть.
            .toolbar(removing: .sidebarToggle)
        } detail: {
            switch selection {
            case .module(let id):
                if let descriptor = modules.descriptors.first(where: { $0.id == id }) {
                    ModuleSettingsDetail(descriptor: descriptor)
                }
            case .general, nil:
                GeneralSettingsView()
            }
        }
        .onChange(of: columnVisibility) { _, newValue in
            if newValue != .all { columnVisibility = .all }
        }
        .frame(minWidth: 760, minHeight: 500)
    }
}

/// Строка боковой панели как в Системных настройках:
/// длинное название переносится на вторую строку, а иконка стоит
/// напротив первой строки текста. Справа — необязательный элемент.
/// Размер иконки следует настройке «Размер значков боковой панели», чтобы
/// иконка и текст масштабировались вместе.
private struct SidebarRow<Accessory: View>: View {
    @Environment(\.sidebarRowSize) private var rowSize
    let title: LocalizedStringResource
    let systemImage: String
    let tint: Color
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TintedIcon(systemImage: systemImage, tint: tint, size: iconSize)
                // Центр иконки — на середине первой строки текста (чуть выше базовой линии).
                .alignmentGuide(.firstTextBaseline) { d in
                    d[VerticalAlignment.center] + iconSize * 0.22
                }
            // Без ограничения строк: название целиком, как в Системных настройках.
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            accessory
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

extension SidebarRow where Accessory == EmptyView {
    init(title: LocalizedStringResource, systemImage: String, tint: Color) {
        self.init(title: title, systemImage: systemImage, tint: tint) { EmptyView() }
    }
}

enum SettingsPane: Hashable {
    case general
    case module(String)
}

/// Правая часть для модуля: настройки самого модуля, если он включён,
/// или подсказка, если выключен (тогда модуль даже не создаётся).
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

/// Общая обёртка для страницы настроек модуля: шапка с иконкой,
/// описанием и тумблером, ниже — разделы самого модуля.
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
