import AppKit
import SwiftUI

/// Тема оформления приложения. Хранится в UserDefaults.
/// Применяется ко всему приложению сразу: окно настроек, панель в строке меню, окно истории.
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearance.theme"

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` — следовать системной теме.
    private var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    static var saved: AppTheme {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppTheme.init(rawValue:)) ?? .system
    }

    func apply() {
        NSApp.appearance = appearance
    }
}
