# Design philosophy

The notch should feel like hardware: one black surface, part of the screen's edge, that
grows, shows something and settles back. The rules below keep that true whatever changes: a
new feature, a quick fix, an integration with someone else's plugin, an Omarchy update ported
in.

If a change can't keep one of these rules, the change is wrong, not the rule. Each rule names
the check that holds it. A rule without a check is a wish, so new rules come with numbers.

## 1. Pitch black

- The notch is one colour: `color`, `#000000` by default (true black, so an OLED pixel is
  off). The resting notch, the open notch, the settings, the menu and every integrated
  plugin's panel all sit on that one colour.
- Nothing inside it has a colour of its own. No theme background, no card colour, no
  gradient, no translucency, no blur.
- Nothing is laid over the screen around it: no scrim, no dimming, no border around the notch.
- Widgets drawn in the notch get the notch colour as their `background`.

Checked by: `dev/glow.sh` (inside the notch: pure black, fully opaque), `dev/menu.sh` (the
menu's background is the notch colour), `dev/colours.sh` (widgets' background is the notch).

## 2. Apple white text

- Text on the black notch is **Apple white**, `#FFFFFF`. Secondary text is Apple's secondary
  label, `#EBEBF5` at 60 %. The theme never colours text on the notch, so a light theme's dark
  text can't land on black.
- On a notch set to a light colour, text is Apple black instead (`#000000`, secondary `#3C3C43`
  at 60 %), whichever of the two reads better.
- Accents reach 3:1 (the theme's accent if it does, otherwise the text colour), selected text
  4.5:1, and a selection fill must actually show.
- Secondary text is always the secondary label, never an arbitrary dimmer hue.
- Omarchy's own controls default to theme colours. Everything drawn in the notch is handed the
  notch's colours explicitly: `notchForeground`, `notchAccent`, `notchColor`. That stops at the
  notch's edge: a widget's pop-out panel sits on the theme's background and keeps the theme's
  colours, so the notch never makes something else unreadable.
- A `foreground` setting always wins.

Checked by: `dev/colours.sh` (the contrast function against WCAG values, the white/black
choice recomputed independently, every surface using it).

## 3. The shape

- **One surface hanging from the top edge.** Its top edge is on the screen edge (y = 0) and
  its top corners are square.
- **Bottom corners** are convex, radius `bottomRadius` (default 10).
- **Fillets** are concave, radius `filletRadius` (default 10), centred *outside* the bar at
  (−r, r) and (w + r, r). The screen edge then flows into the sides with no kink.
- It is never a pill, never a cut-out and never a floating card.
- **It changes size, never form.** Opening widens it. The settings, the menu and plugin panels
  grow it downward. The top edge stays on the screen edge and the bottom radius follows the
  setting in every state. While it emerges from the edge, both radii scale with its height.
- **Content lives inside the shape.** Panels, menus and plugin UIs render in the notch, not in
  windows of their own. The one exception is the battery glow. It is light *outside* the shape,
  so it has its own click-through window that never resizes.

Checked by: `dev/geometry.sh` (every radius and arc centre, the tangency arithmetic, pixels
that tell a fused bar from a pill or a notch), `dev/menu.sh` (the menu's notch keeps its top
edge, square top corners and radius, and no extra window exists).

## 4. Seamless, smooth motion

- **Growing** runs on a damped spring with ζ = 0.72, so it overshoots once by 3.8 % and
  settles. The height takes 350 ms. The width starts 50 ms later and takes 300 ms, so both land
  together.
- **Shrinking** eases out (OutCubic) over 240 ms with no overshoot.
- **The entrance** grows from a seed 35 % as wide and zero high, top edge on the screen edge
  from the first frame.
- **Restarts continue.** An animation restarted mid-flight picks up from wherever the notch
  is. It never jumps back to a start value.
- **Content follows the surface.** It fades in over 220 ms as the notch grows and out over
  90 ms. It never changes under a shrinking notch: the view is kept until the notch has closed.
- **The glow** fades in once over 800 ms, then stays still. A colour change crossfades over
  600 ms.
- **Nothing reloads, flashes, pops or jumps.** A flash, a reload-looking frame or a jump in
  layout is a bug against this rule. It is never "just a glitch".

- **No surface showing the notch is ever resized.** Hyprland draws a resized layer's old
  image stretched for a few frames, which blinks. The bar window keeps one height. Tall shapes
  (the settings, the menu, the update notice) draw in a panel window sized once, handing over
  at the resting size where both shapes match.

Checked by: `dev/geometry.sh` (the easing constants and spring curve), `dev/glow.sh` (the
fades, timed), `dev/motion.sh` (corners stay rounded while moving), `dev/surface.sh` (every
layer keeps one size and address, sampled from Hyprland's socket; the handoff never leaves a
gap).

## 5. One radius

- Every button, chip, field, switch, selection highlight, outline, card and tooltip in or
  hanging from the notch uses the **notch's radius**: `bottomRadius`. It is the same number
  everywhere, whatever the theme's Hyprland rounding is. Change the setting and everything
  follows.
- A control shorter than twice the radius is capped at half its height, so it becomes a pill
  instead of a broken corner.
- Circles stay circles: a slider knob, say, or a switch knob that is meant to be round.
- Integrated plugins get the radius from the notch. They don't pick their own.

Checked by: `dev/design.sh`, which walks the settings panel and the menu and checks every
rounded item's radius.

## 6. It feels like a proper product

- **Integration is seamless.** A plugin integrated with the notch looks and moves as if the
  notch had built it: its menus and panels open *inside* the notch, on the notch's colour, in
  the notch's text colours and radius, on the notch's motion.
- **One UI per action.** While the notch hosts a plugin's UI, that plugin's own window, popup
  or animation for the same thing is switched off.
- **Standalone still works.** Without the notch, or if the notch declines, the plugin works
  exactly as it does on its own.
- **Every way in leads to the same place.** A keybind, a click, IPC and the Omarchy menu
  toggle all open the same view, and a keybind works from any state. The open keybind works
  while the settings are open.
- **Nothing is dead.** A control that has nothing to show says why, as the battery preview does
  at a glow size too small to see. A setting that can't apply doesn't pretend.
- **Everything is reversible.** Settings save the moment they change, without a reload. A
  setup fix that edits a file snapshots it first, and Restore puts it back byte for byte; a
  fix that doesn't verify rolls itself back.
- **The keyboard works everywhere.** Escape closes, typing searches, and a picked row runs.
- **Verified by numbers, not by eye.** Radii, centres, timings, contrast and sizes are printed
  and checked. A screenshot is not proof.

Checked by: `dev/setup.sh` (a fix snapshots the files it changes, verifies by re-running
the check, rolls itself back when it doesn't take, and Restore puts the bytes back).

## Before a change lands

1. It still sits on one black surface, with nothing laid over the screen.
2. Every new piece of text or control gets the notch's colours and radius explicitly.
3. The shape and top edge are untouched, and the frozen suites (`dev/geometry.sh`,
   `dev/glow.sh`) pass unchanged.
4. It moves on the notch's spring and fades. Nothing flashes, reloads or jumps.
5. If it hosts a plugin's UI, the plugin's own copy is off while hosted and back when not.
6. It adds numeric checks for anything new, and `./dev/check.sh` passes.
