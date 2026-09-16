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
| **Resting** | A black rectangle at the top centre. Empty by default; can show time, date, now playing. |
| **Peek** | When a new track starts, the notch widens for a few seconds to show it. |
| **Open** | On hover (or click): a top row with the glance items, and your bar widgets under it. It stays open while a widget's panel is open. |
| **Hidden** | `omarchy-toggle-bar` slides it up into the edge. |

## Settings menu

Long right-click the notch (hold for about half a second) to open its settings: how it opens,
whether windows reach the top edge, what it shows at rest and when open, its size and corner
radii, and the battery glow. Every change is saved to `shell.json` straight away. **Preview**
shows the charging, low and critical glow without touching the battery, and stops when the menu
closes. You can also open the menu with `quickshell ipc -p $OMARCHY_PATH/shell call notch settings`.

## Battery glow

Light falls off outward from the notch's edge. It is not a shape and not a blur: every pixel
takes its opacity from its exact distance to the notch's outline, the fillet arcs included
(`shaders/glow.frag`, curve in `glow.js`):

| Distance from the edge | 0–6 px | 20 px | 50 px | 80 px and beyond |
|---|---|---|---|---|
| Opacity | 0.35 | 0.18 | 0.07 | 0 |

Between those points the curve is a monotone cubic Hermite spline. Its slope is zero at 6 px and
at 80 px, so it never steps, never rises, and meets zero without an edge. Nothing is drawn under
the notch.

| State | Colour |
|---|---|
| Charging | amber `#FFB340` |
| Full, on the charger | green `#30D158` |
| Low (≤ 20 %, on battery) | red `#FF453A` |

The glow fades in once over 800 ms (ease-out) and then stays completely still. Charging to full
crossfades the colour over 600 ms. Unplugging fades the glow out over 800 ms, widens the notch to
show the battery, and fades out the charging bolt. The glow has its own full-width, click-through
window (`omarchy-notch-glow`) that is always tall enough for the whole falloff below the open
notch, so it is never cut off and nothing resizes when it turns on or off.

## Settings

Everything lives under `bar.notch` in `~/.config/omarchy/shell.json`, and every key is optional:

```json
"bar": {
  "id": "graveklar.notch",
  "notch": {
    "compact": ["clock", "media"],
    "expanded": ["clock", "date", "media"],
    "expandOn": "hover",
    "color": "#000000",
    "compactWidth": 180,
    "compactHeight": 32,
    "bottomRadius": 10,
    "expandedBottomRadius": 18,
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
| `expanded` | `["clock","date","media"]` | Glance items on the open notch's top row. Leaves out time and date when the layout already has `omarchy.clock`. |
| `expandOn` | `"hover"` | `"hover"` or `"click"`. In click mode, clicking outside closes it. |
| `color` / `foreground` | `#000000` / theme bar text | Notch and glance text colours. |
| `compactWidth`, `compactHeight` | `180`, `32` | Resting size, in logical px. The height is also what windows keep clear. |
| `bottomRadius`, `expandedBottomRadius` | `10`, `18` | Convex bottom-corner radius, resting and open. |
| `filletRadius` | `10` | Concave fillet where the notch meets the screen edge. |
| `hoverDelay`, `collapseDelay` | `60`, `350` | Milliseconds. |
| `peekOnTrackChange`, `peekDuration` | `true`, `3500` | Widen briefly on a new track. |
| `batteryGlow` | `true` | The battery glow. |
| `chargingColor`, `fullColor`, `lowColor` | `#FFB340`, `#30D158`, `#FF453A` | Glow colours. |
| `lowBattery`, `criticalBattery` | `20`, `10` | Percent thresholds, on battery. |
| `batteryPeek` | `true` | Widen to show the charge on plug-in, unplug and low battery. |
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
