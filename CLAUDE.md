# CmdPlus — instructions for Claude

## What this is
CmdPlus is a free, open-source macOS app: a set of menu bar utilities instead of a zoo of separate apps.
The author is new to Swift: explain in Russian, briefly — what you did and how to check it.

## Hard rules
- Swift + SwiftUI, Apple system components only. macOS 26 style (Liquid Glass), minimum macOS 26.0.
- The app lives in the menu bar (MenuBarExtra), with no Dock icon (LSUIElement = YES).
- Everything stays local: no servers, accounts or analytics. Only currency rates and update checks go online.
- Modular architecture: every module can be turned on/off in Settings; a disabled module isn't loaded.
- Clipboard passwords and codes are never saved (password storage was removed in 0.1.0). If it ever comes back:
  this Mac's Keychain only, kSecAttrSynchronizable = false, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
  revealed with Touch ID, never included in settings export.
- Don't change signing, Team or Bundle ID (com.azam.CmdPlus).
- Data: settings in UserDefaults, history and the rest in ~/Library/Application Support/CmdPlus.
  When a data format changes, migrate on first launch.
- Ask for permissions (Accessibility, etc.) only when the module is turned on, with a clear explanation.
- Quiet launch at login via SMAppService, no windows at launch; load heavy modules lazily.
- Keep it light on resources but good-looking.
- Localization via String Catalog (currently ru + en). No hard-coded UI strings.
- Never commit secrets, keys or certificates.
- Repo text is in English: code comments, commit messages, README. No Claude co-author lines in commits.

## How to work
- One task at a time. Small, clear changes — no rewriting everything at once.
- After changes, build and run the tests. Cover logic with Swift Testing.
- At the end of each step, briefly: what was done, how to check it manually, what's next.

## Releases
- Free distribution only: `scripts/build-release.sh <version>` builds an ad-hoc signed zip,
  then publish it as a GitHub release.

## Roadmap
1. ✅ App shell (menu bar, tile panel, Settings window) + Clipboard History (⇧⌘V, word search, user-set 1–500 limit, pinned items don't count).
2. ✅ Mouse: smooth/reversible scrolling, speed, actions for any extra button  3. Window management  4. File converter  5. System monitor
6. Small modules: sleep and power, QR and Wi-Fi, currency rates, color picker, text converter, hide menu bar icons, Windows compatibility
7. Polish for 1.0: onboarding, languages, "What's New", settings export, app icon, README, GitHub release
Later: disk analyzer, PDF editor, video compression, key remapping, screen recording, OCR.
