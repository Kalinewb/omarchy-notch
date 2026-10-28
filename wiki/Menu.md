# Menu

The notch has its own copy of Omarchy's menu (`menu/NotchMenu.qml`). When you open it, the notch grows down into the menu: the same rows, search, submenus, Apps list and actions, and the same size as Omarchy's menu card. The difference is that it is drawn inside the notch in the notch's colour (black by default), with no window of its own, no scrim over the screen and no border. The notch's top edge stays on the screen edge, and it grows and shrinks with the spring as you move between menus.

## Menu

*In the notch.* The switch in [Settings](Settings.md#menu) (`replaceMenu`, off by default). On, every way into Omarchy's menu opens the notch's: SUPER + SPACE and the other menu keybinds, `omarchy menu`, the bar's menu button, the screen-recording indicator and every picker. Off, they open Omarchy's own window, exactly as before. The switch takes effect on the next open, with no restart.

- **It needs a one-time set-up**, which the notch does itself: a small companion plugin (`kalinewb.notch-menu`, the folder in `companion/`). Omarchy routes menu calls to whichever plugin says `clonedFrom: omarchy.menu`; the companion's go-between then asks the notch first and falls back to Omarchy's own menu, loaded from `$OMARCHY_PATH`, so nothing is a copy. Enabling it swaps the menu button in your bar layout for its identical one, in place.
- **When the notch can't show it** (the bar is hidden, the notch isn't running or isn't the bar), Omarchy's own menu opens instead. A picker is never left hanging: if no menu can take it, its caller is released.
- **To undo:** turn the switch off, or `omarchy plugin disable kalinewb.notch-menu` from a terminal, which puts `omarchy.menu` back exactly.

If the companion is switched off, not installed, or not noted by Omarchy for restoring, [Setup](Setup-points.md#the-menu-companion-is-switched-off) says so and offers the Fix. Keys of your own that call the notch's menu directly are a separate Setup point: [Menu keys skip the menu toggle](Setup-points.md#menu-keys-skip-the-menu-toggle).

## Opening it

- A gesture from `menuWith` (the gestures that open Omarchy's menu inside the notch; `click`, `doubleClick`, `longPress`, `rightClick`, `longRightClick`, `middleClick`, never `hover` or `scroll`, because the menu takes the keyboard). A gesture belongs to one list: the settings win, then the menu, then *Open with*. `menuWith` has no row; see [Settings with no row](Settings.md#settings-with-no-row).
- The `menuKey` keybind (also without a row).
- *Opens to*, set to **Menu** (`"openAction": "menu"`).
- `omarchy-shell notch menu root`. Instead of `root`, you can pass any menu id or alias (`system`, `power-menu`, `style.font`). An alias for an action runs it directly.

## Closing it

Pick a row, press Escape, click outside, or use the same trigger or call again. The strip at the top centre goes up one menu level on the first press; see [The way back](Settings.md#the-way-back).

## Entries

Menu entries come from the same files as Omarchy's menu: `$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc` and your `~/.config/omarchy/extensions/omarchy-menu.jsonc`. Both are watched for changes.

**Pickers** (emoji, keybindings, timezone, sharing) open in the notch when *Menu* is on, and in Omarchy's window when it is off.

**The Apps list** needs an app library. A bar plugin isn't given one, so the menu loads its own copy of the shell's `AppLibrary` the first time it opens.

## Keeping up with Omarchy

`dev/upstream/menu/` holds Omarchy 4.0.5's `Menu.qml` and `MenuModel.js` exactly as released. `menu/MenuModel.js` is identical to that copy. `menu/NotchMenu.qml` keeps upstream's structure and names, and its header lists every change. After an Omarchy update, compare the installed files with the saved copies:

```sh
diff -u dev/upstream/menu/Menu.qml $OMARCHY_PATH/shell/plugins/menu/Menu.qml
diff -u dev/upstream/menu/MenuModel.js $OMARCHY_PATH/shell/plugins/menu/MenuModel.js
```

Port any changes to the fork, then copy the new files into `dev/upstream/menu/`. `dev/menu.sh` tests the result. [Setup](Setup-points.md#omarchy-changed-upstream) reports a file that changed.
