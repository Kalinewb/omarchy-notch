# Notch

A bar for Omarchy that is a black notch hanging from the top centre of the screen, fused to
the edge the way the Dynamic Island grows out of a MacBook's notch. It rests pitch black. Point
at it (or click it) and it opens to show every widget from your bar layout, plus the time and
what is playing.

It replaces `omarchy.bar` as a full `bar` plugin, and hosts the same widgets and panels.

## Install

From the Omarchy plugin marketplace, or in a terminal:

```sh
omarchy plugin add https://github.com/Kalinewb/omarchy-notch --yes
omarchy plugin enable kalinewb.notch
```

That installs a git checkout, so the notch can update itself, and `omarchy plugin update kalinewb.notch` works too.

## Documentation

How to use it, one page per area, is in the wiki folder: **[Home](https://github.com/Kalinewb/omarchy-notch/blob/master/wiki/Home.md)**. This README keeps what a developer needs.

## Remove

```sh
omarchy plugin remove kalinewb.notch
```

brings back `omarchy.bar`. More in [Plugins](wiki/Plugins.md#removing-the-notch).

## Developing

Commit in this repo, then run `./install.sh`. It fast-forwards the live checkout to your committed HEAD and restarts the shell, without changing where the checkout pulls from; push when the change is ready. It refuses while there are uncommitted changes, which would otherwise silently not be installed. `./install.sh --no-enable` leaves the active bar alone. `./install.sh --swap-to-git` turns an old copied install into a checkout once, and moves the copy to `~/.local/state/kalinewb.notch/backups/` first.

`dev/plugins.sh` tests the Plugins page against sandbox git remotes and a sandbox plugins folder through test hooks, which a test notch passes on: `NOTCH_PLUGINS_DIR`, `NOTCH_PLUGINS_OMARCHY`, `NOTCH_PLUGINS_CATALOGUE`, `NOTCH_PLUGINS_SHELL`, `NOTCH_PLUGINS_TERMINAL`, `NOTCH_PLUGINS_SESSION_LOCKED`, `NOTCH_PLUGINS_SCRATCH` (any of these without both `NOTCH_PLUGINS_DIR` and `NOTCH_PLUGINS_OMARCHY` refuses every command), `NOTCH_PLUGINS_STATE_DIR` (only in a sandbox), `NOTCH_PLUGINS_DISCOVER_MS`, `NOTCH_PLUGINS_DONE_MS`, `NOTCH_PLUGINS_DETACH` and `NOTCH_PLUGINS_RESTART`. A sandboxed update that finishes a rename also needs `NOTCH_SETUP_SANDBOX`, and runs Setup as a test, so Setup's own guard holds too. A test notch never checks or acts unless `NOTCH_FORCE_PLUGINS=1` and the sandbox hooks are set. `dev/update.sh` tests the notch's own update against a sandbox git remote, `dev/setup.sh` Setup, `dev/osd.sh` the OSD and `dev/menu.sh` the menu.

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

The outline style is not that curve: it is a diffuse glow, a gaussian-like bell peaking at 0.16
right at the notch's edge (no flat top, so no rim), reaching zero 1.6 times as far out as the reach
above (`Glow.diffuse`, profile in `glow.js`). Along the top edge of the screen the glow does not stop
at the fillet tip: it tapers outward, running three times as far along the edge as it reaches down,
so it fades out instead of being cut off at its brightest (`edgeTail` 3 in `shaders/glow.frag`; below
and beside the bar nothing changes). Neither is a setting. `dev/glow-fade.sh` checks both.

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
strip replaced by the notch. `menu/` is Omarchy's `omarchy.menu` (MIT), drawn inside the notch. The island shape and spring curve come from Face ID (kalinewb.face).

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
