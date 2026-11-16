# CmdPlus

A free, open-source set of small utilities for macOS that lives in your menu bar — one lightweight app instead of a pile of separate ones.

- **Native.** Swift and SwiftUI, system components only, designed for macOS 26 and Liquid Glass.
- **Light on resources.** Disabled modules aren't even loaded; heavy work happens in the background.
- **Private.** Everything stays on your Mac. No accounts, no servers, no analytics.
- **Modular.** Turn each tool on or off in Settings.

## Modules

### Clipboard History

Keeps the text, images and files you copy and lets you get them back in a second.

- Press **⇧⌘V** to open a Spotlight-style window with a list on the left and a preview on the right.
- Search by words in any order, with matches highlighted. Filter by text, images, files, pinned or passwords.
- Pick an item and it's **pasted straight into the app you were using**. No extra ⌘V needed.
- **Drag** items into any app: text as text, images as PNG, files as files.
- **Pin** what you need often. Pinned items never count toward the limit.
- Choose how many items to keep, from **1 to 500**. The oldest unpinned ones are removed first.
- **Passwords and codes** copied from password managers are stored only in this Mac's Keychain. They are never synced to iCloud, are shown as dots, are revealed with Touch ID and expire automatically.

| Shortcut | Action |
| --- | --- |
| ⇧⌘V | Open the history window, bring it forward, or close it |
| ↑ ↓ | Move the selection |
| ↩ or double-click | Paste the item |
| ⌥↩ | Copy without pasting |
| ⌘1 … ⌘9 | Paste one of the first nine items |
| ⌘P | Pin or unpin |
| ⌘⌫ | Delete |
| esc | Close |

More modules are on the way. See the [roadmap](#roadmap).

## Requirements

- macOS 26 or later
- To build: Xcode 27 or later

## Building

1. Clone the repository:
   ```sh
   git clone https://github.com/GostWarrir186/CmdPlus.git
   ```
2. Open `CmdPlus.xcodeproj` in Xcode.
3. In **Signing & Capabilities**, pick your own team (the project is signed with the author's team by default).
4. Press **⌘R** to run. CmdPlus appears in the menu bar. It has no Dock icon.

Run the tests with **⌘U**, or from the terminal:

```sh
xcodebuild -project CmdPlus.xcodeproj -scheme CmdPlus -destination 'platform=macOS' test
```

## Permissions

CmdPlus asks for a permission only when you turn on the feature that needs it, and explains why.

| Permission | Used for |
| --- | --- |
| Accessibility | Pasting a picked history item for you by sending ⌘V. Without it, items are only copied. |
| Touch ID / password | Revealing or pasting a saved password. |

## Privacy

- Settings are stored in `UserDefaults`.
- History is stored in `~/Library/Containers/com.azam.CmdPlus/Data/Library/Application Support/CmdPlus/`.
- Passwords are stored only in the Keychain. They are never written to disk in plain text and never included in exports.
- The only planned network access is currency rates and update checks. Clipboard History never goes online.

## Roadmap

1. ✅ App shell and Clipboard History
2. Reverse mouse scrolling
3. Window management
4. File converter
5. System monitor
6. Small tools: sleep and power, QR and Wi-Fi, currency rates, color picker, text converter, hide menu bar icons, Windows-friendly shortcuts
7. Polish for 1.0: onboarding, languages, "What's New", settings export, app icon, release

## Contributing

Issues and pull requests are welcome. Please keep the spirit of the project: native, fast, private.

## License

[MIT](LICENSE)
