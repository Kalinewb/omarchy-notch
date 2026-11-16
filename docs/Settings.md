# Settings

Long press (or right-click and hold) the notch, or run `omarchy-shell notch settings`, and the
notch grows into the Settings panel. It is quiet on purpose: eight rows under three headings
(**Look**, **Open**, **In the notch**), and one fold, **Advanced**, closed every time the panel
opens. A row is a label on the left and its state on the right. Rest the pointer on a row, or
walk to it with the arrow keys, and the line under the list says what it does.

The keyboard does all of it. Up and Down walk the rows, Left and Right step a number or walk an
open list, Space or Enter flips, opens or records, and Escape closes the tip, then the open list,
then the panel. **Tab** reaches the header buttons and the buttons inside a row. The Needs attention page answers to
the same keys: Up and Down over its rows, Enter to press a row's button.
**Reset to defaults** asks twice: the button turns into *Sure?* for three seconds, and only a
second press inside that time deletes your settings. Escape answers no.

*Notification light* and *Light colours* are held back until the notch can draw them.

## The header

`Notch`, then up to three buttons, then `✕`.

- **Plugins** is always there and opens the Plugins page, where Face ID, Profiles and OLED
  Corners are installed. It reads **Plugins · n** when something has an update: `n` counts the
  notch's own update (1 when GitHub has a newer version) plus every plugin with a verified update
  ready. At zero it is just **Plugins**.
- **n need attention** (**1 needs attention**) opens the Needs attention page. It is not there at zero; Advanced → **Check for problems** (*None*, or the count) opens the same page. The notch counts 20 seconds after it starts, every 6 hours and when Settings opens, so this is current without anyone asking.
- **Guided setup** appears once the notch has a guided setup to start.

A badge is a count on a header button, shown only above 0. It is never on a row or a section.

**The Plugins count is partly blind.** It only counts what the notch already knows and never
goes looking. The notch checks for its own update 20 seconds after it starts and every 6 hours
(unless *Check for updates* is off), so that half is current. Plugin updates are checked when
the Plugins page opens, so the plugin half reads 0 until you have visited Plugins once in this
session. Opening Plugins (it is one press away, from this very button) brings it up to date.

## Settings with no row

Seventeen `bar.notch` keys have no row in the panel: six whose default is the design, and eleven
that never had one. They are all still read, still exported, and still yours to change from a
terminal:

```sh
omarchy-shell notch set <key> <value>
```

List keys take space-separated values (`omarchy-shell notch set settingsWith "rightClick longPress"`);
anything else is JSON if it parses (`omarchy-shell notch set compactHeight 36`), a string if not.
A value written by hand survives every change you make in the panel and goes only with
*Reset to defaults*. Setting a key back to its default is harmless.

| key | default | effect | set it |
|---|---|---|---|
| `settingsWith` | `longRightClick` | The gestures that open Settings: any of `hover click doubleClick longPress rightClick longRightClick middleClick scroll`. A gesture listed here is not offered by *Open with*. | `omarchy-shell notch set settingsWith "rightClick longPress"` |
| `menuWith` | none | The gestures that open Omarchy's menu inside the notch (never `hover` or `scroll`). Settings win a gesture both claim, then the menu, then *Open with*. | `omarchy-shell notch set menuWith middleClick` |
| `menuKey` | none | A Hyprland key combination that toggles the menu, e.g. `SUPER + ALT + M`. | `omarchy-shell notch set menuKey "SUPER + ALT + M"` |
| `stateKey` | none | A key combination that shuts the notch where it stands and opens it where it stood. For anyone working on a panel. | `omarchy-shell notch set stateKey "SUPER + ALT + S"` |
| `compactHeight` | `32` | The resting notch's height in pixels, never below the bar's height. | `omarchy-shell notch set compactHeight 36` |
| `criticalBattery` | `10` | The battery level (%) at or under which, while discharging, the notch treats the battery as critical. *Low battery at* sets the level above it. | `omarchy-shell notch set criticalBattery 5` |
| `color` | `#000000` | The notch's fill. Pitch black is the design. | `omarchy-shell notch set color "#101010"` |
| `foreground` | white on a dark notch, black on a light one | The colour of text and controls on the notch, and of its accent. | `omarchy-shell notch set foreground "#E5E5E5"` |
| `chargingColor` | `#FFB340` | The glow while charging. | `omarchy-shell notch set chargingColor "#FFD60A"` |
| `fullColor` | `#30D158` | The glow when the battery is full. | `omarchy-shell notch set fullColor "#32D74B"` |
| `lowColor` | `#FF453A` | The glow at a low battery. | `omarchy-shell notch set lowColor "#FF9F0A"` |
| `hoverDelay` | `60` | Milliseconds the pointer rests on the notch before hover acts. | `omarchy-shell notch set hoverDelay 120` |
| `collapseDelay` | `350` | Milliseconds after the pointer leaves before the notch folds back. | `omarchy-shell notch set collapseDelay 600` |
| `peekDuration` | `3500` | Milliseconds a peek (a new track, a charger) stays out; at least 500. | `omarchy-shell notch set peekDuration 5000` |
| `hoverAction` | none | Legacy. `clock`, `battery` or `plugin` read as the matching *On hover* items and widget. Use `hoverItems` and `hoverPlugins` (the *On hover* row) instead. | `omarchy-shell notch set hoverAction clock` |
| `hoverPlugin` | none | Legacy companion of `hoverAction: plugin`: the widget to preview. | `omarchy-shell notch set hoverPlugin omarchy.clock` |
| `expandOn` | none | Legacy. `click` reads as *Open with* = Click alone; otherwise the default is Hover and Click. Use `openWith` (the *Open with* row) instead. | `omarchy-shell notch set expandOn click` |

Powers the panel no longer offers beyond these keys: any notification time from 1 to 60 seconds
(the *Notification time* row offers five; `omarchy-shell notch set notificationSeconds 45` sets
the rest, and the row then shows `45 s`), and the battery glow preview, which is
`omarchy-shell notch simulateBattery charging 64`.
