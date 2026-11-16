import SwiftUI

/// Menu bar tile: a click turns reverse scrolling on or off.
struct MouseTileView: View {
    let module: MouseModule

    var body: some View {
        let descriptor = MouseModule.descriptor
        let settings = module.settings

        ModuleTile(
            title: descriptor.title,
            subtitle: subtitle,
            systemImage: descriptor.systemImage,
            tint: settings.reverseVertical ? descriptor.tint : .gray,
            action: toggle
        )
        .help(Text(module.hasAccess ? "Turn reverse scrolling on or off" : "Allow Access…"))
    }

    private var subtitle: String {
        guard module.hasAccess else { return String(localized: "Permission needed") }
        return module.settings.reverseVertical
            ? String(localized: "Reverse scrolling on")
            : String(localized: "Reverse scrolling off")
    }

    private func toggle() {
        guard module.hasAccess else {
            module.requestAccess()
            return
        }
        module.settings.reverseVertical.toggle()
    }
}
