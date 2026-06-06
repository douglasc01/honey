# 🍯 Honey — an 8-bit macOS desk companion

Honey is a tiny pixel-art character that lives on your Mac. The sprite **animates
live in your menu bar** while you work, and a larger version sits **on your
desktop** for when you tidy your windows away. Throughout the day Honey quietly
gets on with little tasks — sipping coffee, watering plants, reading, dozing off —
switching activity every few minutes.

It's a lightweight menu-bar app (no Dock icon), built in Swift with SwiftUI + AppKit.

> **Heads up:** Honey is distributed **unsigned** (ad-hoc signed, not notarized by
> Apple). It's safe, but macOS will warn you the first time you open it — see
> [First launch](#first-launch-important) below for the one-time step.

---

## Features

- 🎞️ **12 animations** — idle, sleeping, waking, coffee, computer, reading,
  eating, exercise, watering plants, music, waving, dancing.
- 🧠 **Time-aware** — leans toward sleeping at night and coffee in the morning.
- 🪟 **Two places at once** — animated in the menu bar *and* on the desktop.
- 📏 **Resizable** — Small / Medium / Large (96 / 128 / 160 px), crisp integer scaling.
- 📌 **Pin to any corner**, or drag it anywhere.
- 🗂️ **Layering** — sit *behind* your windows (a calm background companion) or
  stay *always on top*.
- 💾 **Remembers your settings** across restarts.

---

## Requirements

- macOS **13 (Ventura)** or later
- Apple Silicon **or** Intel (the release is a universal binary)

---

## Install

1. Download **`Honey-macOS.zip`** from the [Releases](../../releases) page.
2. Unzip it and drag **`Honey.app`** into your **Applications** folder.

### First launch (important)

Because the app isn't notarized by Apple, Gatekeeper blocks it on the first run.
Pick **one** of these:

**Option A — Right-click to open**
1. In Applications, **right-click** (or Control-click) `Honey.app` → **Open**.
2. In the dialog, click **Open** again.

   *(You only need to do this once. On macOS 15+ you may instead get a prompt in
   **System Settings → Privacy & Security** with an "Open Anyway" button.)*

**Option B — Terminal (one command)**
```bash
xattr -dr com.apple.quarantine /Applications/Honey.app
```
Then double-click as normal.

Honey has **no Dock icon** — look for the animated sprite in your **menu bar**
(top-right). Click it for the menu.

---

## Using Honey

Click the menu-bar sprite:

| Menu item | What it does |
|-----------|--------------|
| **Show on Desktop** | Toggle the larger desktop companion on/off. |
| **Size** | Small (96 px) · Medium (128 px) · Large (160 px). |
| **Pin to Corner** | Bottom Right / Bottom Left / Top Right / Top Left. (You can also just drag it.) |
| **Layer** | **Behind Everything** (covered by your windows, visible on the desktop) or **Always on Top**. |
| **Activity** | Jump to a specific animation. It keeps auto-rotating afterward. |
| **Quit Honey** | Quit. |

All choices are saved and restored next time you launch.

---

## Build from source

You'll need Apple's **Command Line Tools** (`xcode-select --install`) — full Xcode
is not required.

```bash
# Quick local build + run (native architecture)
./build.sh
open Honey.app

# Release build: universal (arm64 + x86_64), signed, zipped to dist/
./package.sh
```

Project layout:

```
Sources/Honey/
  main.swift         # NSApplication bootstrap (.accessory = no Dock icon)
  AppDelegate.swift  # menu-bar item, animated icon, window, menu, settings
  Honey.swift        # animation + activity-scheduling engine
  ContentView.swift  # SwiftUI Canvas that draws the pixels
  SpriteData.swift   # decodes the sprite sheet + palette
  Resources/
    honey-sprites.json  # source of truth: palette + 12 tasks × frames (32×32)
Info.plist           # bundle metadata (LSUIElement, min OS, etc.)
build.sh             # dev build
package.sh           # release build → dist/Honey-macOS.zip
```

### Troubleshooting

- **`error: redefinition of module 'SwiftBridging'`** when building — your Command
  Line Tools have a stale modulemap. Fix:
  ```bash
  sudo mv /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap{,.bak}
  ```

---

## Uninstall

1. Quit Honey (menu → **Quit Honey**).
2. Delete `/Applications/Honey.app`.
3. (Optional) remove saved settings:
   ```bash
   defaults delete com.honey.desk-companion
   ```

---

## Notes & limitations

- **Unsigned / not notarized.** This is a hobby build; the [first-launch step](#first-launch-important)
  is required. For warning-free distribution you'd need an Apple Developer ID +
  notarization.
- The "menu bar while working, desktop when idle" effect is achieved *passively*
  via the **Behind Everything** layer — Honey doesn't actively detect whether the
  desktop is showing.
- The on-screen label uses **Menlo** (always installed). Drop in a pixel font like
  *Press Start 2P* and tweak `ContentView.swift` if you want the full retro look.
