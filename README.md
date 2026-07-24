# SplitScreen

A macOS menu bar app that puts your windows back where you keep them. One
shortcut (`⌃⌥⌘R`) restores a saved layout after a monitor unplug or a
maximized window scrambles everything.

![Before and after](assets/before-after.png)

## Why

On a laptop screen my layout is always the same: terminal and notes stacked in
a narrow column on the left, editor and browser filling the rest. macOS
forgets it. Unplug an external monitor and every window lands somewhere
random, then you rebuild the arrangement by hand. SplitScreen snapshots the
arrangement once and puts it back on demand.

It stores exactly one layout. Saving again overwrites it.

## Install

Requires macOS 14+ and the Swift toolchain (Xcode Command Line Tools is
enough).

```sh
git clone https://github.com/hunterphillips/split-screen.git
cd split-screen
./make-dev-cert.sh        # one time: create a stable local signing identity
./build-app.sh install    # build, copy to /Applications, launch
```

`make-dev-cert.sh` creates a self-signed certificate so rebuilds keep their
Accessibility approval. Without it the build falls back to ad-hoc signing, and
on macOS Tahoe each ad-hoc rebuild needs Accessibility granted again.

On first launch, macOS asks for **Accessibility** access (System Settings →
Privacy & Security → Accessibility). The menu unlocks once it's granted. For
CLI use, the terminal running the binary needs its own Accessibility grant.

## Use

- Arrange your windows, then press `⌃⌥⌘S` or choose **Save Current Layout**.
- Press `⌃⌥⌘R` or choose **Restore Layout** to put everything back.
- Click the menu bar icon for the menu, the shortcut hints, and the
  **Launch at Login** toggle.

Restore also works while docked: frames are stored relative to the built-in
display, so you can gather everything onto the laptop screen first and then
pull the cable.

## CLI

The same binary runs headless:

```sh
SplitScreen --save        # snapshot the current windows
SplitScreen --restore     # apply the saved layout
SplitScreen --list        # print visible windows and frames
```

The layout is plain JSON at
`~/Library/Application Support/SplitScreen/layout.json`.

## How it works

Save reads the Accessibility window list of every regular app and records each
visible, standard, non-minimized window's frame as an offset from the built-in
display's top-left corner.

Restore pairs saved and live windows by app and window order, never by title
(browser tab titles change constantly). It applies each frame as
size → position → size, because macOS otherwise clamps windows to fit whatever
display they currently occupy, then reads the frame back and retries briefly
on a mismatch. Chromium apps get `AXEnhancedUserInterface` disabled during the
move; with it on, a single resize can stall Chrome for seconds.

Restore skips minimized and fullscreen windows, windows on other Spaces
(macOS offers no public API for those), apps that aren't running, and windows
opened after the save. A skip never aborts the rest of the restore.

## Development

```sh
swift build && swift test   # unit tests cover coordinates, matching, persistence
./build-app.sh              # assemble and sign the bundle in place
./test-restore.sh           # optional smoke test; needs Accessibility access
```

## Roadmap

v2: an opt-in trigger that restores automatically when the display
configuration becomes laptop-only. v1 does no display watching at all.

## License

MIT
