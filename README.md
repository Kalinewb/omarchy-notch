# Notch

A bar for Omarchy that is a black notch hanging from the top centre of the screen, fused to
the edge the way the Dynamic Island grows out of a MacBook's notch. It rests pitch black. Point
at it (or click it) and it opens to show every widget from your bar layout, plus the time and
what is playing.

It replaces `omarchy.bar` as a full `bar` plugin, and hosts the same widgets and panels.

## Install

```sh
omarchy plugin add https://github.com/Kalinewb/omarchy-notch --yes
omarchy plugin enable graveklar.notch
```

That installs a git checkout, so `omarchy plugin update graveklar.notch` updates it.

### Updates

When GitHub has a newer notch, the resting notch pops down into a small notice with **Later**
and **Update**. Update installs it in the background and restarts the shell, and the notch then
says "Notch updated" for a few seconds. Later hides that version until a newer one comes out. If
an update fails, the notice shows why until you dismiss it. Opening the notch covers the notice,
and hovering it never opens the notch, so the pointer can reach the buttons.

The notch checks 20 seconds after it starts and every 6 hours after that. A check fetches
origin's HEAD into `.git` and nothing else, so it never reloads plugins. Settings → Updates shows
where things stand (up to date, available, a development install ahead of GitHub, local edits,
offline) and has Check now. `updateCheck: false` turns checking off.

The update runs as `bin/notch-update run` in its own `systemd-run --user` unit, because the
update reloads every plugin and destroys the notch that started it. It runs
`omarchy plugin update graveklar.notch --yes`, decides success from where the checkout ends up
(not from the exit code), and writes its progress to `$XDG_RUNTIME_DIR/graveklar.notch/update.json`.
Over IPC: `notch update check|now|later|dismiss|status`. `dev/update.sh` tests the lot against
a sandbox git remote.

**Developing:** commit in this repo, then run `./install.sh`. It fast-forwards the live
checkout to your committed HEAD and restarts the shell, without changing where the checkout
pulls from; push when the change is ready. It refuses while there are uncommitted changes, which
would otherwise silently not be installed. `./install.sh --no-enable` leaves the active bar alone.
`./install.sh --swap-to-git` turns an old copied install into a checkout once, and moves the copy
to `~/.local/state/graveklar.notch/backups/` first.

Go back to another bar with `omarchy plugin enable omarchy.bar` (or your own clone).

## How it behaves

| State | What you see |
|---|---|
| **At rest** | A black rectangle at the top centre. Empty by default; can show time, date, now playing and battery. |
| **Peek** | A new track, plugging in, unplugging or a low battery widens the notch for a few seconds. |
| **On hover** | If hover opens the notch (`openWith`), the open view. Otherwise your hover items (time, date, media, battery) next to your hover plugins, in one row. Either closes when the pointer leaves. |
| **When open** | What `openAction` says, for every other way of opening it (click, keybind, …). |
| **Settings** | The notch grows down into its settings panel -- the same surface, top edge on the screen edge. |
| **Menu** | The notch grows down into the Omarchy menu, black like the rest of the notch. See [Omarchy menu](#omarchy-menu). |
| **Hidden** | `omarchy-toggle-bar` slides it up into the edge; with `autoHide`, it also hides at rest until the pointer reaches for it. |

The open notch is one row at the resting height: it only widens. Only the settings panel and the
menu make it taller. The widget row is the same row for every view, so a single-plugin view shows that
plugin's live widget and never loads a second copy.

### Ways to open it

`openWith`, `settingsWith` and `menuWith` pick the gestures for the notch, the settings and the
Omarchy menu (hover, click, double-click, long press, right-click, long right-click, middle-click,
scroll; the menu takes no hover or scroll). `openKey`, `settingsKey`, `menuKey` and `autoHideKey`
add keybinds for opening the notch, the settings and the menu, and for toggling auto-hide. In the settings each has a **Record** button: press it, then the combination
(Escape cancels). Plain letters need SUPER, CTRL or ALT; F-keys work alone. A gesture belongs to one list at a time
(the settings win, then the menu).

The open keybind works from any state. From the settings or the menu it goes straight to the
open view, or just closes the panel when the open action is that panel. A view opened by a
keybind stays until you press the keybind again, or until the pointer has been over the notch
and left. It doesn't rely on Hyprland's click-outside grab, which unrelated focus changes clear.

**Keep the notch open** (`stayOpen`, with `stayOpenKey`) keeps the open view up whatever the
pointer does. The settings and the menu still open over it, and it comes back when they close. Keybinds go into the running
Hyprland with `hyprctl eval`, are replaced when changed, and are re-added after every config
reload; nothing is written to your Hyprland config. Hyprland keeps runtime binds across a shell
restart, so every apply reconciles with Hyprland's own bind list (`bin/notch-keybinds`): a bind
already there is left alone, duplicates and stale notch binds are removed, and a key that also
carries a bind of your own is never touched.

## Settings panel

Open the settings with a long right-click (by default) or its keybind. The notch grows into the
panel; click outside, press Escape or ✕ to close it. Every change is saved to `shell.json` straight
away. **Preview** (under Battery) shows the charging, full and low glow without touching the battery,
until you pick Off or close the settings. It shows the glow at your current glow size. At a tiny size
(under 4 px) or with the glow off there is nothing to see, and a note under Preview says so.

Over IPC: `quickshell ipc -p $OMARCHY_PATH/shell call notch expand|collapse|toggle|settings|peek|geometry`,
`view widgets|clock|battery|plugin|settings`, `menu <route>`, `windowsToTop true|false|toggle`, and
`simulateBattery charging|discharging|full|auto <percent>`.

## Omarchy menu

The notch has its own copy of Omarchy's menu (`menu/NotchMenu.qml`). When you open it, the notch
grows down into the menu. Same rows, search, submenus, Apps list and actions, and the same size
as Omarchy's menu card. The difference: it's drawn inside the notch in the notch's colour (black
by default), with no window of its own, no scrim over the screen and no border. The notch's top
edge stays on the screen edge. It grows and shrinks with the spring as you move between menus.

- **Open it** with a gesture from `menuWith`, the `menuKey` keybind, `"openAction": "menu"`, or
  `quickshell ipc -p $OMARCHY_PATH/shell call notch menu root`. Instead of `root`, you can pass
  any menu id or alias (`system`, `power-menu`, `style.font`). An alias for an action runs it
  directly.
- **Close it** by picking a row, pressing Escape, clicking outside, or using the same trigger or
  call again.
- **Omarchy's own menu doesn't change.** SUPER + SPACE (and the menu keybinds that go with it),
  `omarchy menu` and the stock bar's menu button still open Omarchy's window. If you record
  SUPER + SPACE as `menuKey`, both menus open: the notch never removes a bind it didn't make. To
  have SUPER + SPACE open only the notch's menu, point that binding in your Hyprland config at
  `omarchy-shell -q notch menu root` instead.
- **Menu entries come from the same files** as Omarchy's menu:
  `$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc` and your
  `~/.config/omarchy/extensions/omarchy-menu.jsonc`. Both are watched for changes.
- **Pickers still open in Omarchy's window.** Some rows start a script that asks Omarchy's menu for
  a choice (emoji, keybindings, timezone, sharing). Those pickers appear there, not in the notch.
- **The Apps list** needs an app library. A bar plugin isn't given one, so the menu loads its own
  copy of the shell's `AppLibrary` the first time it opens.

**Keeping up with Omarchy.** `dev/upstream/menu/` holds Omarchy 4.0.3's `Menu.qml` and
`MenuModel.js` exactly as released. `menu/MenuModel.js` is identical to that copy.
`menu/NotchMenu.qml` keeps upstream's structure and names, and its header lists every change. After
an Omarchy update, compare the installed files with the saved copies:

```sh
diff -u dev/upstream/menu/Menu.qml $OMARCHY_PATH/shell/plugins/menu/Menu.qml
diff -u dev/upstream/menu/MenuModel.js $OMARCHY_PATH/shell/plugins/menu/MenuModel.js
```

Port any changes to the fork, then copy the new files into `dev/upstream/menu/`. `dev/menu.sh`
tests the result.

## Plugin contract

Everything the notch shows is a plugin described by one descriptor (`contract.js`): `id`, `kind`,
`label`, `closedView`, `expandedView`, `preferredHeight` (a request; the notch decides),
`priority` (`transient`, `persistent`, `persistent-low`), `groupable` and `hideable`.

- **Built-ins** use reserved ids: `notch.clock`, `notch.date`, `notch.media`, `notch.battery`,
  `notch.settings` and `notch.menu`. Both of the last two have `hideable: false`, and their
  `expandedView` is the settings panel or the menu.
- **Bar widgets** keep the id your layout already uses. An adapter describes every one with
  defaults (`persistent-low`, groupable, hideable, the live widget as its closed view), so a widget
  needs no changes.
- **Opting in:** a widget can expose a `notch` property, a plain object with any of those fields,
  to override the defaults. Invalid values fall back to the default and are reported.
- **Your config doesn't change format:** settings keep short names (`"clock"`) and widget ids;
  short names map to reserved ids only when read.
- **Expanded views:** each one renders through the same host type inside the notch.
- **Hiding:** `hiddenPlugins` has no effect on a plugin that declares `hideable: false`, and the
  picker shows it locked.

`quickshell ipc -p $OMARCHY_PATH/shell call notch contract` prints the registry.
`dev/contract.sh` checks the migration against a baseline recorded before it (synthetic configs plus
your own `shell.json`, kept in the gitignored `dev/baselines/local/`), and checks the contract itself.

## Battery glow

Light falls off outward from the edge of the notch **at rest**. It keeps that shape while the notch
is open or grown into its settings. It is not a shape and not a blur: every pixel takes its opacity
from its exact distance to the resting notch's outline, the fillet arcs included
(`shaders/glow.frag`, curve in `glow.js`). The curve is set relative to the notch. With
`glowScale` 1.0 it reaches zero at the resting height (32 px by default):

| Distance from the edge (× reach / 80) | 0–6 | 20 | 50 | 80 and beyond |
|---|---|---|---|---|
| Opacity | 0.35 | 0.18 | 0.07 | 0 |

So at the default 32 px reach: 0.35 up to 2.4 px, 0.18 at 8 px, 0.07 at 20 px, 0 from 32 px.
Between those points the curve is a monotone cubic Hermite spline, with zero slope at both ends.

| State | Colour |
|---|---|
| Charging | amber `#FFB340` |
| Full, on the charger | green `#30D158` |
| Low (≤ 20 %, on battery) | red `#FF453A` |

**Bottom style** (`glowStyle: "bottom"`): the same falloff at 0.24 instead of 0.35, only below the
bottom edge, weighted cos²(π·u/2) across it: full in the middle, half at a quarter of the width in
from each side, nothing at the sides.

**When the notch widens or grows** (open, or the settings panel), the glow moves to the bottom of
the notch as it is then, in the bottom style, following its live width and corner radius; it
hands over from the resting glow within the first 24 px of growth and comes back at rest.

The glow fades in once over 800 ms (ease-out) and then stays completely still. Charging to full
crossfades the colour over 600 ms. Unplugging fades the glow out over 800 ms, widens the notch to
show the battery, and fades out the charging bolt. The glow has its own click-through window
(`omarchy-notch-glow`) that never resizes.

## Widget reloads

When `shell.json` or a plugin changes on disk, Omarchy reloads the bar. It can hand a third-party
bar a widget catalogue that still refers to the previous load, which leaves widgets empty until
the shell restarts. The notch checks for that 2.5 s after loading and, if any widget is empty,
asks for one plugin rescan, which refreshes the catalogue. It does this at most once every 30 s.
Changes made from the settings panel don't reload the bar.

## Settings

Everything lives under `bar.notch` in `~/.config/omarchy/shell.json`, and every key is optional:

```json
"bar": {
  "id": "graveklar.notch",
  "notch": {
    "compact": ["clock", "media"],
    "expanded": ["clock", "date", "media"],
    "openWith": ["hover", "click"],
    "hoverItems": ["clock", "media"],
    "hoverPlugins": ["quickshell.spotify"],
    "openAction": "widgets",
    "settingsKey": "SUPER + ALT + N",
    "menuWith": ["middleClick"],
    "color": "#000000",
    "compactWidth": 180,
    "compactHeight": 32,
    "bottomRadius": 10,
    "filletRadius": 10,
    "peekOnTrackChange": true,
    "windowsToTop": false
  },
  "layout": { "left": [], "center": [], "right": [] }
}
```

| Key | Default | Meaning |
|---|---|---|
| `compact` | `[]` | Glance items in the resting notch: `clock`, `date`, `media`, `battery`. Empty keeps it pitch black. |
| `expanded` | `["clock","date","media"]` | Glance items added to the widget row. Leaves out time and date when the layout already has `omarchy.clock`. |
| `openWith` | `["hover","click"]` | Gestures that open the notch: `hover`, `click`, `doubleClick`, `longPress`, `rightClick`, `middleClick`, `scroll`. |
| `settingsWith` | `["longRightClick"]` | Gestures that open the settings, from the same list plus `longRightClick`. |
| `menuWith` | `[]` | Gestures that open the Omarchy menu inside the notch: `click`, `doubleClick`, `longPress`, `rightClick`, `longRightClick`, `middleClick`. |
| `openKey`, `settingsKey`, `menuKey`, `autoHideKey` | none | Keybinds, e.g. `"SUPER + N"`, recorded from the settings. |
| `hoverItems`, `hoverPlugins` | `[]`, `[]` | What hovering shows when hover isn't in `openWith`: any of `clock`, `date`, `media`, `battery`, next to any widgets (by id), in one row. With hover in `openWith`, hovering opens the notch instead. |
| `openAction`, `openPlugin` | `"widgets"` | The same, for every other way of opening it. `openAction` can also be `"settings"` or `"menu"`. |
| `hiddenPlugins` | `[]` | Widget ids left out of the open notch's row. They stay loaded and can still be the hover or open plugin. |
| `color` / `foreground` | `#000000` / Apple white | Notch colour, and the colour of text on it. Text is Apple white (`#FFFFFF`, secondary `#EBEBF5` at 60 %) on a dark notch and black on a light one, whatever the theme. Widgets in the notch, the settings and the menu use it too. |
| `compactWidth`, `compactHeight` | `180`, `32` | Resting size, in logical px. The height is also what windows keep clear. |
| `bottomRadius` | `10` | Convex bottom-corner radius, in every state including the settings panel. |
| `filletRadius` | `10` | Concave fillet where the notch meets the screen edge. |
| `hoverDelay`, `collapseDelay` | `60`, `350` | Milliseconds. |
| `updateCheck` | `true` | Check GitHub for a newer notch and pop down a notice when there is one. |
| `peekOnTrackChange`, `peekDuration` | `true`, `3500` | Widen briefly on a new track. |
| `batteryGlow` | `true` | The battery glow. |
| `glowScale` | `1.0` | Glow reach relative to the resting notch's size (0–2.5, at most 80 px). 0 draws no glow. |
| `glowStyle` | `"outline"` | `"outline"`: around the resting notch. `"bottom"`: subtler (0.24 at its brightest), only under the bottom edge, strongest in the middle. |
| `chargingColor`, `fullColor`, `lowColor` | `#FFB340`, `#30D158`, `#FF453A` | Glow colours. |
| `lowBattery`, `criticalBattery` | `20`, `10` | Percent thresholds, on battery. |
| `greenAbove` | `100` | Charging at or above this percentage already shows the full colour (green). 100 means only a full battery does. |
| `batteryPeek` | `true` | Widen to show the charge on plug-in, unplug and low battery. |
| `stayOpen`, `stayOpenKey` | `false`, none | Keep the notch open on its open view (the widgets when the open action is a panel). The keybind toggles it. |
| `autoHide` | `false` | The resting notch hides in the screen edge until the pointer reaches the top edge above it (a 3 px strip a little wider than the notch). Peeks, the open notch and the settings still show, over the windows. |
| `windowsToTop` | same as `autoHide` | `false`: windows stay below the resting notch. `true`: windows go all the way to the top edge, under the notch. Follows `autoHide` unless you set it. The space kept clear never changes while you use the notch, so windows don't resize when it opens, peeks, hides or reveals. |

Widgets are still placed with `omarchy bar move` and `omarchy plugin enable/disable`.

## The shape

`Island.qml` builds the shape from three items: the bar and two fillets.

- **The bar**: a plain `Rectangle`. Its top edge is on the screen edge, its top corners are
  square, and its bottom corners have an ordinary convex radius. Nothing is cut out of it.
- **Two fillets**, drawn outside the bar in the angle between each side and the screen edge.
  Each one is an r×r square minus a quarter-disc centred at (−r, r) and (w + r, r) in the
  bar's coordinates. Those arcs are tangent to both the screen edge and the bar's side, so the
  edge curves into the bar with no kink.

A circle tangent to both of those lines has to be centred one radius from each. Put the centre
inside the bar, at (r, r), and the arc lies inside the bar: that is a notch cut out of it. A
positive radius on the top corners makes a floating pill.

While the notch grows out of the edge, both radii scale with its height, so it never passes
through a pill shape. Growth runs on a damped spring (ζ = 0.72, about 3.8 % overshoot): the
height takes 350 ms, and the width starts 50 ms later and takes 300 ms, so both land together.
Shrinking eases out over 240 ms with no overshoot.

`dev/geometry.sh` checks this as numbers. It runs the real `Bar.qml` in a throwaway
Quickshell instance, reads every radius and arc centre over IPC (resting and open), checks the
tangency arithmetic, then renders `Island.qml` offscreen at those sizes and samples the pixels
that separate a fused bar from a pill or a notch.

`dev/glow.sh` does the same for the glow. It simulates each battery state over IPC and samples
the fade and crossfade with timestamps. Then it renders the glow offscreen, where
`dev/glow_pixels.py` traces the outline, fillets included, as a dense polyline. It measures every
pixel's distance to the outline by brute force and checks each pixel's opacity against the curve.

## Credits

`Bar.qml` and `BarModel.js` start from Omarchy's `omarchy.bar` (MIT), with the full-width
strip replaced by the notch. `menu/` is Omarchy's `omarchy.menu` (MIT), drawn inside the notch. The island shape and spring curve come from graveklar.face.

## Checks

```sh
./dev/check.sh            # QML lint, then every suite
./dev/check.sh keys       # lint, then just the named suites
```

`dev/lint.sh` runs `qmllint` with `qs.*` resolved against the installed Omarchy shell, because a
QML error in a third-party plugin never reaches the journal: the plugin just doesn't appear. It
fails on a non-zero exit or on any warning that means QML won't load or bind (syntax, import,
missing or unresolved types, …) beyond the ones Omarchy's own `Bar.qml` produces. Our `Bar.qml`
is vendored from it, and that allowance is recomputed from the installed file on every run.
Members "not found on type QObject" are expected (`bar` is injected untyped). `install.sh` runs
the lint before installing anything.

Test notches (the suites start throwaway Quickshell instances) ignore Omarchy's `bar-off` toggle
and never touch Hyprland keybinds; only the notch Omarchy's shell hosts does either.
