# Realign

Realign puts your Mac windows back where you had them.

![Before and after](assets/before-after.png)

Arrange your windows once and save. When something scrambles them, press one
shortcut and they snap back. It remembers two arrangements: one for the
laptop on its own, and one for each set of monitors you plug into. It can
also restore on its own when you plug in or unplug.

It lives in the menu bar, is free, and is open source (MIT).

## Install

Requires macOS 14 or later and the Xcode Command Line Tools. Right now you
build it from source, which takes about a minute:

```sh
git clone https://github.com/hunterphillips/realign.git
cd realign
./make-dev-cert.sh        # once: creates a local signing certificate
./build-app.sh install    # builds the app, copies it to /Applications, opens it
```

The first script makes a certificate so that rebuilding the app doesn't make
macOS ask for permission again. Skip it and everything still works, but on
macOS Tahoe you'll be asked after every rebuild.

On first launch, macOS asks for Accessibility access. Turn it on in System
Settings under Privacy & Security, then Accessibility. The app needs this to
move other apps' windows.

## How to use

1. Arrange your windows the way you like them.
2. Press `⌃⌥⌘S`, or click the menu bar icon and choose **Save Current Layout**.
3. Later, when your windows are a mess, press `⌃⌥⌘R`. They go back.

Do step 1 and 2 once with the laptop on its own and once with your monitors
plugged in. The app saves each as its own layout and knows which is which.

The menu has a few more things in it:

- **Restore Laptop Layout** and **Restore Multi-Display Layout** restore one
  specific layout, whatever is plugged in. Restoring the laptop layout while
  monitors are attached gathers every window onto the laptop screen, which is
  handy right before you unplug.
- **Restore Shortcut** picks what `⌃⌥⌘R` does. **Auto-detect**, the default,
  restores the layout for whatever monitors are connected, or the laptop
  layout if you haven't saved one for them. The other two choices pin the
  shortcut to one layout.
- **Auto-Restore on Display Change** does the restore for you. Unplug your
  monitors and the laptop layout comes back a couple of seconds later. Plug
  them in and the monitor layout comes back. It's off by default. If you dock
  somewhere you haven't saved a layout for, it leaves your windows alone.
  Same when you unplug without a saved laptop layout.
- **Launch at Login** does what it says.

Saving again replaces the layout for the monitors connected at that moment.

## Good to know

- Restore only moves windows that were open when you saved, matched by app and
  by order. If you saved with one browser window and now have two, only one
  moves. Save again and both will.
- Minimized windows, full-screen windows, and windows on other desktops stay
  where they are. Apps that aren't running are skipped.
- With the lid closed there's no laptop screen, so the laptop layout can't be
  restored until you open it.

## Why I built it

On my laptop screen the layout is always the same: terminal and notes in a
narrow column on the left, editor and browser filling the rest. macOS doesn't
remember it. Unplug a monitor and every window lands somewhere random, and I'd
rebuild the arrangement by hand several times a day. Now it's one key.

## How it works

When you save, the app asks macOS for the position and size of every visible
window and writes them down relative to the screen each window is on. When
you restore, it finds each of those windows again and moves it back.

Two details make this reliable. Each window is resized, then moved, then
resized again, because macOS otherwise squeezes a window to fit the screen it
is currently on before it can move. And after every move the app reads the
window's position back and retries briefly if it didn't land, instead of
trusting that the move worked.

Monitors are recognized by the identifier macOS gives them, with a fallback on
make, model, and size in case that identifier changes when a monitor is moved
to a different port. Chrome and other Chromium apps get one accessibility
setting switched off during the move, because with it on, a single resize can
freeze Chrome for several seconds.

## Command line

The same binary works from a terminal, which needs its own Accessibility
permission:

```sh
Realign --save              # save the layout for the connected displays
Realign --restore           # restore what the shortcut would
Realign --restore laptop    # restore the laptop layout
Realign --restore multi     # restore the layout for the connected displays
Realign --list              # show connected displays and every window
```

Layouts and settings are a plain JSON file at
`~/Library/Application Support/Realign/layouts.json`. A `layout.json`
from an older version is read into the laptop layout the first time and left
where it is.

## Development

```sh
swift build && swift test   # unit tests cover coordinates, matching, persistence,
                             # display resolution, and target selection
./build-app.sh              # assemble and sign the bundle in place
./test-restore.sh           # optional smoke test; needs Accessibility access
```

## License

MIT
