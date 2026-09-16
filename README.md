# Notch

A bar for Omarchy that is a black notch hanging from the top centre of the screen, fused to
the edge the way the Dynamic Island grows out of a MacBook's notch. It rests pitch black. Point
at it (or click it) and it opens to show every widget from your bar layout, plus the time and
what is playing.

It replaces `omarchy.bar` as a full `bar` plugin, and hosts the same widgets and panels.

## Install

```sh
./install.sh              # copy into ~/.config/omarchy/plugins, restart the shell, make it the bar
./install.sh --no-enable  # copy only
```

Go back to another bar with `omarchy plugin enable omarchy.bar` (or your own clone).

## How it behaves

| State | What you see |
|---|---|
| **At rest** | A black rectangle at the top centre. Empty by default; can show time, date, now playing and battery. |
| **Peek** | A new track, plugging in, unplugging or a low battery widens the notch for a few seconds. |
| **On hover** | If hover opens the notch (`openWith`), the open view. Otherwise your hover items (time, date, media, battery) next to your hover plugins, in one row. Either closes when the pointer leaves. |
| **When open** | What `openAction` says, for every other way of opening it (click, keybind, …). |
| **Settings** | The notch grows down into its settings panel -- the same surface, top edge on the screen edge. |
| **Hidden** | `omarchy-toggle-bar` slides it up into the edge; with `autoHide`, it also hides at rest until the pointer reaches for it. |

The open notch is one row at the resting height: it only widens. Only the settings panel makes
it taller. The widget row is the same row for every view, so a single-plugin view shows that
plugin's live widget and never loads a second copy.

### Ways to open it

`openWith` and `settingsWith` pick the gestures for the notch and for the settings (hover, click,
double-click, long press, right-click, long right-click, middle-click, scroll). `openKey`,
`settingsKey` and `autoHideKey` add keybinds for opening the notch, opening the settings and
toggling auto-hide. In the settings each has a **Record** button: press it, then the combination
(Escape cancels). Plain letters need SUPER, CTRL or ALT; F-keys work alone. A gesture belongs to one list at a time. Keybinds go into the running
Hyprland with `hyprctl eval`, are replaced when changed, and are re-added after every config
reload; nothing is written to your Hyprland config. Hyprland keeps runtime binds across a shell
restart, so every apply reconciles with Hyprland's own bind list (`bin/notch-keybinds`): a bind
already there is left alone, duplicates and stale notch binds are removed, and a key that also
carries a bind of your own is never touched.

## Settings panel

Open the settings with a long right-click (by default) or its keybind. The notch grows into the
panel; click outside, press Escape or ✕ to close it. Every change is saved to `shell.json` straight
away. **Preview** shows the charging, full and low glow without touching the battery.

Over IPC: `quickshell ipc -p $OMARCHY_PATH/shell call notch expand|collapse|toggle|settings|peek|geometry`,
`view widgets|clock|battery|plugin|settings`, `windowsToTop true|false|toggle`, and
`simulateBattery charging|discharging|full|auto <percent>`.

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
| `openKey`, `settingsKey`, `autoHideKey` | none | Keybinds, e.g. `"SUPER + N"`, recorded from the settings. |
| `hoverItems`, `hoverPlugins` | `[]`, `[]` | What hovering shows when hover isn't in `openWith`: any of `clock`, `date`, `media`, `battery`, next to any widgets (by id), in one row. With hover in `openWith`, hovering opens the notch instead. |
| `openAction`, `openPlugin` | `"widgets"` | The same, for every other way of opening it. |
| `hiddenPlugins` | `[]` | Widget ids left out of the open notch's row. They stay loaded and can still be the hover or open plugin. |
| `color` / `foreground` | `#000000` / theme bar text | Notch and glance text colours. |
| `compactWidth`, `compactHeight` | `180`, `32` | Resting size, in logical px. The height is also what windows keep clear. |
| `bottomRadius` | `10` | Convex bottom-corner radius. The settings panel uses 20 % of its height, between this and 24 px. |
| `filletRadius` | `10` | Concave fillet where the notch meets the screen edge. |
| `hoverDelay`, `collapseDelay` | `60`, `350` | Milliseconds. |
| `peekOnTrackChange`, `peekDuration` | `true`, `3500` | Widen briefly on a new track. |
| `batteryGlow` | `true` | The battery glow. |
| `glowScale` | `1.0` | Glow reach relative to the resting notch's size (0–2.5, at most 80 px). 0 draws no glow. |
| `glowStyle` | `"outline"` | `"outline"`: around the resting notch. `"bottom"`: subtler (0.24 at its brightest), only under the bottom edge, strongest in the middle. |
| `chargingColor`, `fullColor`, `lowColor` | `#FFB340`, `#30D158`, `#FF453A` | Glow colours. |
| `lowBattery`, `criticalBattery` | `20`, `10` | Percent thresholds, on battery. |
| `greenAbove` | `100` | Charging at or above this percentage already shows the full colour (green). 100 means only a full battery does. |
| `batteryPeek` | `true` | Widen to show the charge on plug-in, unplug and low battery. |
| `autoHide` | `false` | The resting notch hides in the screen edge until the pointer reaches the top edge above it (a 3 px strip a little wider than the notch). Peeks, the open notch and the settings still show. Windows use the full height. |
| `windowsToTop` | `false` | `false`: windows stay below the resting notch. `true`: windows go all the way to the top edge, under the notch. |

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
strip replaced by the notch. The island shape and spring curve come from graveklar.face.

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
