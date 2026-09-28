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

On first launch, macOS asks for Accessibility access, which Realign needs to move windows.

## How to use

1. Arrange your windows.
2. Press `⌃⌥⌘S` or choose **Save Current Layout** from the menu bar dropdown.
3. Press `⌃⌥⌘R` to restore.

Realign keeps one layout for the laptop and one for each set of external monitors. Saving again overwrites the layout for the current display setup.

Menu options:

- **Restore Laptop Layout** and **Restore Multi-Display Layout** restore a specific layout regardless of which displays are connected.
- **Restore Shortcut** chooses what `⌃⌥⌘R` restores: the layout matching the connected displays (default), the laptop layout, or the multi-display layout.
- **Auto-Restore on Display Change** restores the matching layout on its own when you plug in or unplug a monitor. It's off by default.

## Why I built it

On my laptop the layout is always the same: terminal and notes in a narrow column on the left, editor and browser filling the rest. macOS doesn't remember it. Every time I unplugged a monitor, every window landed somewhere random and I rebuilt the arrangement by hand, several times a day.

## How it works

When you save, Realign records the position and size of every visible window relative to the display it's on. When you restore, it moves each window back and checks that it landed. Displays are matched by the ID macOS assigns them, with make, model, and size as a fallback.

## License

MIT
