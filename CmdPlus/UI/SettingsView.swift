import SwiftUI

/// Окно настроек в стиле Системных настроек:
/// слева «Основные» и список модулей с тумблерами, справа — параметры выбранного пункта.
///
/// Боковая панель фиксированной ширины, как в Системных настройках: её нельзя
/// ни сузить, ни скрыть. Поэтому здесь не `NavigationSplitView` (у него край
/// всегда можно перетащить), а простая раскладка: панель + разделитель + содержимое.
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
                    // Тумблер модуля — в шапке его страницы справа, в боковой панели его нет.
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

/// Строка боковой панели как в Системных настройках:
/// длинное название переносится на вторую строку, а иконка стоит
/// напротив первой строки текста.
/// Размер иконки следует настройке «Размер значков боковой панели», чтобы
/// иконка и текст масштабировались вместе.
private struct SidebarRow: View {
    @Environment(\.sidebarRowSize) private var rowSize
    let title: LocalizedStringResource
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TintedIcon(systemImage: systemImage, tint: tint, size: iconSize)
                // Центр иконки — на середине первой строки текста (чуть выше базовой линии).
                .alignmentGuide(.firstTextBaseline) { d in
                    d[VerticalAlignment.center] + iconSize * 0.22
                }
            // Без ограничения строк: название целиком, как в Системных настройках.
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
