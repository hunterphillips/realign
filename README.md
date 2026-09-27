# Realign

Realign puts your Mac windows back where you had them.

![Before and after](assets/before-after.png)

Arrange and save your window layout. Quickly restore a saved layout with a keyboard shortcut or restore automatically when you plug in or unplug external monitors.

## Install

Requires macOS 14 or later.

```sh
brew install hunterphillips/tap/realign
```

Or download the zip from the [latest release](https://github.com/hunterphillips/realign/releases/latest) and drag Realign to your Applications folder.

Or build it yourself:

```sh
git clone https://github.com/hunterphillips/realign.git
cd realign
./build-app.sh install
```

On first launch, grant Accessibility access in System Settings > Privacy & Security > Accessibility. Realign needs it to move other apps' windows.

## How to use

1. Arrange your windows.
2. Press `⌃⌥⌘S`, or choose **Save Current Layout** from the menu bar icon.
3. Press `⌃⌥⌘R` to restore.

Realign keeps one layout for the laptop on its own and one for each set of external monitors. Save once in each setup. Saving again overwrites the layout for the current setup.

Menu options:

- **Restore Laptop Layout** and **Restore Multi-Display Layout** restore a specific layout regardless of what is connected. Restoring the laptop layout while monitors are attached moves every window onto the laptop screen, useful before unplugging.
- **Restore Shortcut** sets which layout `⌃⌥⌘R` restores. Auto-detect, the default, picks the layout for the connected monitors, or the laptop layout if none is saved for them.
- **Auto-Restore on Display Change** restores the matching layout a few seconds after you plug in or unplug monitors. It is off by default. If no layout is saved for the new setup, nothing moves.

## Good to know

- Restore moves only windows that existed when you saved, matched by app and order. If you saved with one browser window and now have two, only one moves.
- Minimized windows, full-screen windows, and windows on other desktops stay where they are. Apps that aren't running are skipped.
- The laptop layout can't be restored with the lid closed.
- Layouts are stored in `~/Library/Application Support/Realign/layouts.json`.

## Why I built it

On my laptop the layout is always the same: terminal and notes in a narrow column on the left, editor and browser filling the rest. macOS doesn't remember it. Every time I unplugged a monitor, every window landed somewhere random and I rebuilt the arrangement by hand, several times a day.

## How it works

When you save, Realign asks macOS for the position and size of every visible window and records them relative to the screen each window is on. When you restore, it finds each window again and moves it back.

Each window is resized, then moved, then resized again, because macOS otherwise shrinks a window to fit its current screen before it moves. After every move, Realign reads the position back and retries if the window didn't land.

Monitors are identified by the ID macOS assigns them, with make, model, and size as a fallback in case the ID changes between ports. For Chrome and other Chromium apps, one accessibility setting is switched off during the move. With it on, a single resize can freeze Chrome for several seconds.

## License

MIT
