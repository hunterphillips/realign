# Realign

macOS menu bar utility and CLI for snapshotting visible window frames and
restoring them. Keeps a laptop layout plus one multi-display layout per set of
connected displays.

## Stack

- Swift 6, SwiftPM executable, macOS 14+
- AppKit for screens, running applications, and menu bar UI
- ApplicationServices Accessibility API for window reads/writes
- Carbon `RegisterEventHotKey` for `⌃⌥⌘R` and `⌃⌥⌘S`
- ServiceManagement `SMAppService.mainApp` for launch at login
- No Xcode project and no third-party dependencies

## Structure

- `main.swift` — GUI/CLI dispatch
- `AppDelegate.swift` — status item, menu, feedback, permission polling
- `HotKey.swift` — simultaneous Carbon hotkey registrations
- `LoginItem.swift` — login-item registration
- `AXPermission.swift` — trust check and prompt
- `WindowEnumerator.swift` — all AX discovery and filtering
- `AXWindow.swift` — thin AX attribute wrapper
- `Coordinates.swift` — all AX/AppKit/stored coordinate conversion
- `Displays.swift` — live display set, fingerprint, anchor/resolve/match logic
- `Models.swift` — Codable layout library data and v1 migration
- `LayoutStore.swift` — atomic JSON persistence of `layouts.json`; migrates v1
  `layout.json` into the laptop slot on load
- `CaptureEngine.swift` — list and save paths, save routing by display set
- `RestoreEngine.swift` — target selection, per-display resolution, verified
  frame application
- `DisplayChangeWatcher.swift` — debounced display-set watcher
- `assets/app-icon.svg` → `AppIcon.icns`; `assets/menubar-icon.svg` →
  `MenuBarIcon.png` / `@2x` (18pt template glyph, drawn on the pixel grid).
  `build-app.sh` copies them into `Contents/Resources`; the status item falls
  back to the SF Symbol `rectangle.split.2x1` outside the bundle.

## Build and verify

```sh
swift build
swift test
./build-app.sh
codesign -dv --verbose=4 Realign.app
```

Use `./build-app.sh install` for the installed daily-driver copy. Run
`./make-dev-cert.sh` once so development builds retain a stable signing
identity and Accessibility approval.

`./build-app.sh release` signs with the keychain's Developer ID Application
identity (`--timestamp`, hardened runtime), notarizes through the
`realign-notary` notarytool keychain profile, staples, and writes
`dist/Realign-<CFBundleShortVersionString>.zip` plus its SHA-256. Bump
`CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist` before
tagging a release.

## Invariants

- Apply every frame in the order **size → position → size**.
- Read back the frame and verify within 2pt. Do not treat AX setter status
  codes as overall success. Retry after 25ms and again after 100ms.
- Read `AXEnhancedUserInterface` on the application element. If true, disable
  it while applying all windows for that app, then restore it.
- Match nth-saved to nth-live by bundle identifier and AX window-list order.
  Never match by title.
- Keep every coordinate-space conversion in `Coordinates.swift`.
  `NSScreen.screens[0]`, not `NSScreen.main`, defines the AppKit/AX flip.
- Stored frames are offsets from the anchor display's top-left, in points,
  with y increasing downward. Each `WindowRecord.displayUUID` names its
  anchor. Do not scale on a resolution mismatch.
- Display identity is the UUID, with fallback to vendor + model + size, then
  to the built-in display.
- `DisplayConfiguration.current()` is the only place that reads `NSScreen`
  for display identity.
- Never overwrite an unreadable `layouts.json`: a load error aborts the save.
- Resolution claims: an exact UUID match claims its live display; the
  vendor+model+size fallback only considers unclaimed displays; the built-in
  fallback is shared.
- If no saved display resolves (e.g. lid closed with no matching
  multi-display layout), the restore is not applied: one reason line,
  `applied == false`, CLI exit 1.
- Skips and failures are per-window. Never abort the rest of a restore.
- Display watching uses only `NSApplication.didChangeScreenParametersNotification`,
  debounced 1.5 s, and acts only when the display fingerprint changed. No
  CoreGraphics reconfiguration callbacks, no polling.
- Automatic restores never prompt for Accessibility and are silent when no
  layout applies.
- No named layouts, app launching, Space manipulation, or settings UI beyond
  the menu toggles.
- Do not enable App Sandbox; public AX window control is incompatible with it.
- Keep the stable `realign-dev` signing path. Ad-hoc signatures can cause
  macOS Tahoe to re-prompt for Accessibility after every rebuild.

## Writing

Hunter edits the README and every other user-facing sentence himself and
expects to do it once. Before drafting or revising any prose, load the
`writing` skill and run its audit. Rules that came out of the 2026-09-27
README sweep:

- The reader is a stranger deciding whether to download. Anything they
  wouldn't care about at that moment is cut, not trimmed: implementation
  details, edge cases, file paths, build or CLI sections, common sense
  ("can't restore with the lid closed"), and anything that only makes sense
  because of a conversation Hunter had.
- No self-referential or reassuring lines ("free and open source", "signed
  and notarized so it opens without extra steps"). No meta lead-ins ("the
  menu has a few more things", "two details make this reliable"). No cute
  filler ("does what it says", "when your windows are a mess"). No
  appositive asides (", the default,", ", useful before unplugging").
- README sections: intro line, image, one paragraph, Install, How to use
  (steps, then menu options), License. Nothing else. Hunter cut Why I
  built it and How it works on 2026-09-27; do not add them back.
- Sentences Hunter wrote stay verbatim. Check `git diff README.md` before
  editing and keep his changes.
