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

Windows keep the resting height clear at the top; the open notch floats over them.

IPC: `quickshell ipc -p $OMARCHY_PATH/shell call notch expand|collapse|toggle|peek|geometry`.

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
    "peekOnTrackChange": true
  },
  "layout": { "left": [], "center": [], "right": [] }
}
```

| Key | Default | Meaning |
|---|---|---|
| `compact` | `[]` | Glance items in the resting notch: `clock`, `date`, `media`. Empty keeps it pitch black. |
| `expanded` | `["clock","date","media"]` | Glance items on the open notch's top row. Leaves out time and date when the layout already has `omarchy.clock`. |
| `expandOn` | `"hover"` | `"hover"` or `"click"`. In click mode, clicking outside closes it. |
| `color` / `foreground` | `#000000` / theme bar text | Notch and glance text colours. |
| `compactWidth`, `compactHeight` | `180`, `32` | Resting size, in logical px. The height is also what windows keep clear. |
| `bottomRadius`, `expandedBottomRadius` | `10`, `18` | Convex bottom-corner radius, resting and open. |
| `filletRadius` | `10` | Concave fillet where the notch meets the screen edge. |
| `hoverDelay`, `collapseDelay` | `60`, `350` | Milliseconds. |
| `peekOnTrackChange`, `peekDuration` | `true`, `3500` | Widen briefly on a new track. |
| `reserve` | `true` | Keep the resting height clear for windows. |

Widgets are still placed with `omarchy bar move` and `omarchy plugin enable/disable`.

## The shape

`Island.qml` holds the shape, in three parts:

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

## Credits

`Bar.qml` and `BarModel.js` start from Omarchy's `omarchy.bar` (MIT), with the full-width
strip replaced by the notch. The island shape and spring curve come from graveklar.face.
