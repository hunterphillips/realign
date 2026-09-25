# RestoreLayout

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

## Build and verify

```sh
swift build
swift test
./build-app.sh
codesign -dv --verbose=4 RestoreLayout.app
```

Use `./build-app.sh install` for the installed daily-driver copy. Run
`./make-dev-cert.sh` once so development builds retain a stable signing
identity and Accessibility approval.

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
- No named layouts, app launching, Space manipulation, or settings UI beyond
  the menu toggles.
- Do not enable App Sandbox; public AX window control is incompatible with it.
- Keep the stable `restore-layout-dev` signing path. Ad-hoc signatures can cause
  macOS Tahoe to re-prompt for Accessibility after every rebuild.

