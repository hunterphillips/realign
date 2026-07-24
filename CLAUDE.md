# SplitScreen

macOS menu bar utility and CLI for snapshotting visible window frames and
restoring them relative to the built-in display.

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
- `Models.swift` — Codable layout data
- `LayoutStore.swift` — atomic JSON persistence
- `CaptureEngine.swift` — list and save paths
- `RestoreEngine.swift` — pure matching and verified frame application

## Build and verify

```sh
swift build
swift test
./build-app.sh
codesign -dv --verbose=4 SplitScreen.app
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
- Stored frames are offsets from the built-in display's top-left, in points,
  with y increasing downward. Do not scale on a resolution mismatch in v1.
- Skips and failures are per-window. Never abort the rest of a restore.
- V1 is hotkey/manual only: no display notifications, debounce, polling,
  named layouts, app launching, Space manipulation, or settings UI.
- Do not enable App Sandbox; public AX window control is incompatible with it.
- Keep the stable `split-screen-dev` signing path. Ad-hoc signatures can cause
  macOS Tahoe to re-prompt for Accessibility after every rebuild.

