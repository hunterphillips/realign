# Realign

Realign resets your Mac window positions & sizing back to a saved layout.

![Before and after](assets/before-after.png)

Arrange and save your window layout. Restore a saved layout with a keyboard shortcut or automatically when you plug in or unplug external monitors.

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

On first launch, macOS asks for Accessibility access, which Realign needs to move windows.

## How to use

1. Arrange your windows.
2. Press `⌃⌥⌘S` or choose **Save Current Layout** from the menu bar dropdown.
3. Press `⌃⌥⌘R` to restore.

Realign keeps one layout for the laptop and one for each set of external monitors. Saving again overwrites the layout for the current display setup.

Menu options:

- **`Restore Laptop Layout`** and **`Restore Multi-Display Layout`** - restore a specific layout regardless of which displays are connected.
- **`Restore Shortcut`** - chooses what the keyboard shortcut restores: the layout matching the connected displays (default), the laptop layout, or the multi-display layout.
- **`Auto-Restore on Display Change`** - Trigger restore layout when you plug in or unplug a monitor. Off by default.

## License

MIT
