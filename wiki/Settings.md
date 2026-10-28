# Settings

Long right-click the notch (hold the right button down), or run `omarchy-shell notch settings`, and the notch grows into the Settings panel. It is quiet on purpose: nine rows under three headings (**Look**, **Open**, **In the notch**), and one fold, **Advanced**, closed every time the panel opens. A row is a label on the left and its state on the right.

Every change is saved to `bar.notch` in `~/.config/omarchy/shell.json` straight away, and shows on the notch at once. Rest the pointer on a row (400 ms), or walk to it with the arrow keys (250 ms), and a one-line tip appears under the list. The panel closes when you click outside it, press Escape or press ✕.

The keyboard: Up and Down walk the rows (the Advanced line, then its rows when it is open), Left and Right change a stepper or move between the lines of an open row, Space or Enter flips a switch or opens a row, and Escape hides the tip, then closes an open row, then closes the panel. The header buttons are reached with Tab. While a key recorder is listening, Escape only cancels the recording.

## The header

`Notch`, then up to three buttons, then `✕`.

- **Updates · n** opens the [Plugins](Plugins.md) page. `n` counts the notch's own update (1 when GitHub has a newer version) plus every plugin with a verified update ready. The button shows only above 0.
- **Setup · n** opens [Setup](Setup-points.md). `n` is the number of things Setup says need attention. The button is absent in a notch where Setup is not available, such as a test notch.
- **Guided setup** opens a guided setup, in a notch that has one. It is hidden otherwise, and no notch has one yet (see [Getting started](Getting-started.md#guided-setup-coming)).

A badge is a count on a header button, shown only above 0. It is never on a row or a section.

**The Updates count is partly blind.** It only counts what the notch already knows and never goes looking. The notch checks for its own update 20 seconds after it starts and every 6 hours (unless *Check for updates* is off), so that half is current. Plugin updates are checked when the Plugins page opens, so the plugin half reads 0 until you have visited Plugins once in this session. Opening Plugins (one press away, from this very button once there is news) brings it up to date.

## At rest

*Look.* Pick any of **Time**, **Date**, **Media** and **Battery** to show on the resting notch (`compact`, the values `clock`, `date`, `media`, `battery`). With none picked the state reads *Nothing* and the resting notch stays pitch black, which is the default.

## Auto-hide

*Look.* `autoHide`, off by default. The resting notch hides in the screen edge until the pointer reaches the top edge above it (a 3 px strip a little wider than the notch). Peeks, the open notch and the settings still show, over the windows. `omarchy-toggle-bar` hides the whole bar whatever this says. Over IPC: `omarchy-shell notch autoHide true|false|toggle`.

Turning Auto-hide on also lets windows reach the top edge, unless you have set *Windows to the top* yourself.

## Charging glow

*Look.* **Off**, **Outline** or **Bottom** (`batteryGlow`, `glowStyle`; Outline is the default). Light falls off outward from the edge of the notch at rest:

- **Outline** is a diffuse glow around the resting notch.
- **Bottom** is subtler and only under the bottom edge, strongest in the middle and fading to nothing at the sides.

The colours are amber while charging (`#FFB340`), green when full on the charger (`#30D158`) and red at a low battery on battery (`#FF453A`). The glow fades in over 800 ms and then stays still; charging to full crossfades the colour over 600 ms; unplugging fades the glow out, widens the notch to show the battery and fades out the charging bolt. When the notch widens or grows, the glow moves to the bottom of the notch as it is then and comes back at rest. The glow has its own click-through window (`omarchy-notch-glow`) that never resizes. The curve is in the [README](../README.md#battery-glow).

To see a glow without touching the battery:

```sh
omarchy-shell notch simulateBattery charging 64      # also discharging, full, auto
```

`auto` hands the battery back. *Glow size*, *Green from* and *Low battery at* below shape it.

## Open with

*Open.* The gestures that open the notch (`openWith`): **Hover**, **Click**, **Double-click**, **Long press**, **Right-click**, **Middle-click**, **Scroll**. The default is Hover and Click. A gesture another list already uses (the settings or the menu gestures) is shown but cannot be picked; a gesture belongs to one list at a time, the settings winning, then the menu, then this one.

The open keybind (*Keybinds* below) works from any state. From the settings or the menu it goes straight to the open view, or just closes the panel when the open action is that panel.

## Opens to

*Open.* What opening shows (`openAction`, `openPlugin`): **Widgets** (the default), **Clock**, **Battery**, **Settings**, **Menu**, or any single widget from your bar by name. It applies to every way of opening that has no view of its own: a click, a keybind and so on.

## Notifications

*In the notch.* **Notch + toast** (the default), **Notch only** or **Off** (`notifications`, `suppressNativeToast`). The long form, with the companion this needs, is on [Notifications](Notifications.md#notifications).

## Notification light

*In the notch.* **Off**, **Around the notch**, **Top edge** or **Full screen** (`notificationLight`, default off). The row exists and writes the setting. The light it describes is not built yet, so nothing reads this setting today; see [Notifications](Notifications.md#notification-light).

## Menu

*In the notch.* A switch (`replaceMenu`, off by default). On: every way into Omarchy's menu opens the notch's copy. The notch installs the small companion plugin this needs by itself; Setup reports it if that fails. See [Menu](Menu.md#menu).

## Volume and brightness

*In the notch.* A switch (`replaceOsd`, off by default). On: the volume, brightness and media overlays show in the notch instead of Omarchy's card at the bottom of the screen. Needs a companion too. See [Notifications](Notifications.md#volume-and-brightness).

## Advanced

A fold, closed every time the panel opens. It holds the rest of the rows, flat, in the order of use.

## Width

*Advanced.* The resting notch's width, 100 to 600 px in steps of 10 (`compactWidth`, 180 by default). The height is `compactHeight` (32), which has no row; see [Settings with no row](#settings-with-no-row).

## On hover

*Advanced.* What hovering shows without opening the notch: any of Time, Date, Media and Battery, plus any widgets from your bar, in one row (`hoverItems`, `hoverPlugins`). Dimmed, with the state *Hover opens*, while Hover is one of the *Open with* gestures, because then hovering opens the notch instead.

## Hidden widgets

*Advanced.* Widgets left out of the open notch's row (`hiddenPlugins`). They stay loaded and can still be the hover or open view. A widget that declares itself not hideable is shown locked.

## Also in the widget row

*Advanced.* Time, date, media or battery added beside your widgets in the open notch (`expanded`). The default is Time, Date and Media, or only Media when your layout already has `omarchy.clock`.

## Panels

*Advanced.* Which plugin panels are drawn inside the notch, with a state like *2 of 5*. Absent until at least one plugin or widget can be drawn inside the notch. When the notch does not accept a plugin, the reason is in words after its name. The long form is [Integrations](Integrations.md).

## Corners

*Advanced.* One number, 0 to 24 px, that rounds both the notch's lower corners and the curves where it meets the screen edge (`bottomRadius` and `filletRadius`, 10 each by default). If the two differ, as when you set one by hand, the row reads like `10 / 12 px`. Every button, chip and field in the notch uses the same radius, capped at half its height.

## Notification time

*Advanced.* How long the notch's copy of a toast stays: **Until I act**, 3 s, 6 s (the default), 10 s or 30 s (`notificationStay`, `notificationSeconds`). Dimmed while notifications are off. Any whole number from 1 to 60 works by hand (`omarchy-shell notch set notificationSeconds 45`), and the row then reads `45 s`.

## Light colours

*Advanced.* **Aurora** (the default), **Blue** or **White** (`notificationLightColours`). Dimmed while *Notification light* is off. As with that row, nothing draws the light yet.

## Peeks

*Advanced.* **New track** (`peekOnTrackChange`) and **Plug-in and low battery** (`batteryPeek`); both on by default, the state reads *Both*, or *Off* when neither is. A peek shows that one thing for a few seconds (3500 ms by default, `peekDuration`): the battery on its own when the charger goes in, the track on its own when it changes, not the resting glance with it added.

## Glow size

*Advanced.* How far the glow reaches, 0 to 250 % in steps of 5, relative to the resting notch's size and at most 80 px (`glowScale`, default 100 %, which reaches the resting height, 32 px on the default notch). 0 draws no glow.

## Green from

*Advanced.* The charge, 0 to 100 % in steps of 5, from which charging already shows the full colour (`greenAbove`, 100 by default, which means only a full battery does).

## Low battery at

*Advanced.* The charge, 5 to 60 % in steps of 5, at or under which, on battery, the glow and the peek switch to the low colour (`lowBattery`, 20 by default). `criticalBattery` (10) has no row.

## Keybinds

*Advanced.* Four keys, each with a **Record** button: **Open the notch** (`openKey`), **Open settings** (`settingsKey`), **Auto-hide** (`autoHideKey`) and **Keep it open** (`stayOpenKey`). The state reads how many are set. Press Record, then the combination; Escape cancels, ✕ removes the key. Plain letters need SUPER, CTRL or ALT (Shift alone is not enough); F-keys and Print work alone. A combination another notch key already uses is refused, with the reason shown. A clash with a bind of your own in Hyprland is what [Setup](Setup-points.md#a-notch-key-is-already-taken) finds.

Keybinds go into the running Hyprland with `hyprctl eval`, are replaced when changed, and are re-added after every config reload; nothing is written to your Hyprland config. Hyprland keeps runtime binds across a shell restart, so every apply reconciles with Hyprland's own bind list (`bin/notch-keybinds`): a bind already there is left alone, duplicates and stale notch binds are removed, and a key that also carries a bind of your own is never touched. Leftovers are one of the things [Setup](Setup-points.md#leftover-notch-keybinds) checks.

`menuKey` and `stateKey` have no row; see [Settings with no row](#settings-with-no-row).

## Keep open

*Advanced.* `stayOpen`, off by default. Keeps the open view up whatever the pointer does. The settings and the menu still open over it, and it comes back when they close. The *Keep it open* key toggles it. Over IPC: `omarchy-shell notch stayOpen true|false|toggle`.

## Windows to the top

*Advanced.* `windowsToTop`. Off: windows stay below the resting notch. On: windows go all the way to the top edge, under the notch. It follows *Auto-hide* until you set it, and a row is there so that you can undo a choice you made. The space kept clear never changes while you use the notch, so windows don't resize when it opens, peeks, hides or reveals.

## Check for updates

*Advanced.* `updateCheck`, on by default. Asks GitHub now and then whether a newer notch exists. See [Plugins](Plugins.md#the-notch-itself) for what an update does.

## Share settings

*Advanced.* **Copy code** and **Save file**: planned, not built yet. The row is hidden in a notch that cannot export. See [Export and import](Export-and-import.md).

## Use someone's settings

*Advanced.* **Import**: planned, not built yet, and hidden for the same reason. See [Export and import](Export-and-import.md).

## Reset to defaults

*Advanced.* **Reset** deletes the whole `bar.notch` block from `shell.json`, hand-written keys included, and returns every default. It has no undo and no confirmation. The widget layout, `bar.layout`, and your plugins are not touched.

## Settings with no row

Seventeen `bar.notch` keys have no row in the panel: six whose default is the design, and eleven that never had one. They are all still read, and still yours to change from a terminal:

```sh
omarchy-shell notch set <key> <value>
```

List keys (`compact`, `expanded`, `openWith`, `settingsWith`, `menuWith`, `hiddenPlugins`, `hoverItems`, `hoverPlugins`) take space-separated values (`omarchy-shell notch set settingsWith "rightClick longPress"`); anything else is JSON if it parses (`omarchy-shell notch set compactHeight 36`), a string if not. A value written by hand survives every change you make in the panel and goes only with *Reset to defaults*. Setting a key back to its default is harmless.

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

Text on a dark notch is white (`#FFFFFF`, secondary `#EBEBF5` at 60 %) and on a light one black, whatever the theme. Nothing in the notch has a hue: selected, hovered and urgent differ by alpha.

## How the notch behaves

The states, and what you see:

| State | What you see |
|---|---|
| **At rest** | A black rectangle at the top centre. Empty by default; can show time, date, now playing and battery. |
| **Peek** | A new track, plugging in, unplugging or a low battery shows **that one thing** for a few seconds. |
| **On hover** | If hover opens the notch (`openWith`), the open view. Otherwise your hover items next to your hover plugins, in one row. Either closes when the pointer leaves. |
| **When open** | What `openAction` says, for every other way of opening it (click, keybind, ...). |
| **Settings** | The notch grows down into its settings panel, the same surface with its top edge on the screen edge. |
| **Menu** | The notch grows down into the Omarchy menu, black like the rest of the notch. See [Menu](Menu.md). |
| **Hidden** | `omarchy-toggle-bar` slides it up into the edge; with `autoHide`, it also hides at rest until the pointer reaches for it. |

The open notch is one row at the resting height: it only widens. Only the settings panel and the menu make it taller. The widget row is the same row for every view, so a single-plugin view shows that plugin's live widget and never loads a second copy.

## The way back

Escape and ✕ close the lot, which is what you want when you are done and not when you went one page too far. So the notch keeps one step of history per page you opened, and **the strip at the top centre, where the resting notch sits, goes back one step**. The notch's own pages leave that strip clear (their title is on the left of that row and their buttons on the right), a chevron appears under the pointer, and it is there on every page of the notch's own: with a step behind it a press goes back to that page, and at the first page it closes the panel. In the menu the first press goes up one menu level. It is also there on a hosted panel and an integration, where a press closes them. Over IPC: `omarchy-shell notch back`.

**Close it here, open it here** (`stateKey`) shuts the notch where it stands and opens it where it stood, the same page and view. It is for working on a panel: testing a change means shutting the notch and opening it again, and without it that is the walk back in through the menus every time. Over IPC: `omarchy-shell notch state`, which answers `stashed`, `closed`, `restored` or `nothing to restore`.

## Over IPC

Every call is `omarchy-shell notch <function>` (or `quickshell ipc -p $OMARCHY_PATH/shell call notch <function>`):

- `expand`, `collapse`, `toggle`, `settings`, `peek`
- `view widgets|clock|battery|plugin|settings|setup`, `menu <route>`
- `autoHide`, `stayOpen`, `windowsToTop` with `true|false|toggle`
- `set <key> <value>`, `simulateBattery charging|discharging|full|auto <percent>`
- `back`, `state`
- `update check|now|later|dismiss|status`, `plugins open|open:<id>|close|status|refresh`

## Every key in shell.json

Everything lives under `bar.notch` in `~/.config/omarchy/shell.json`, and every key is optional:

```json
"bar": {
  "id": "kalinewb.notch",
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
| `replaceOsd` | `false` | Omarchy's volume, brightness and media overlays show in the notch. |
| `replaceMenu` | `false` | Every way into Omarchy's menu opens the notch's menu. |
| `notifications` | `true` | Omarchy's toasts also show in the notch. |
| `notificationStay`, `notificationSeconds` | `false`, `6` | How long the notch's copy of a toast stays: until you act on it, or this many seconds, 1 to 60. |
| `suppressNativeToast` | `false` | The notch is the only place a toast shows. |
| `notificationLight`, `notificationLightColours` | `"off"`, `"aurora"` | Stored by their rows; not read by anything yet. |
| `menuWith` | `[]` | Gestures that open the Omarchy menu inside the notch: `click`, `doubleClick`, `longPress`, `rightClick`, `longRightClick`, `middleClick`. |
| `openKey`, `settingsKey`, `menuKey`, `autoHideKey`, `stateKey`, `stayOpenKey` | none | Keybinds, e.g. `"SUPER + N"`. |
| `hoverItems`, `hoverPlugins` | `[]`, `[]` | What hovering shows when hover isn't in `openWith`: any of `clock`, `date`, `media`, `battery`, next to any widgets (by id), in one row. |
| `openAction`, `openPlugin` | `"widgets"` | What opening shows. `openAction` is `widgets`, `clock`, `battery`, `plugin`, `settings` or `menu`; `openPlugin` names the widget for `plugin`. |
| `hiddenPlugins` | `[]` | Widget ids left out of the open notch's row. |
| `hostedPanels`, `disabledIntegrations` | `[]`, `[]` | Behind the *Panels* row: widgets whose own panel is drawn in the notch, and plugin integrations switched off. |
| `color` / `foreground` | `#000000` / white | Notch colour, and the colour of text on it. |
| `compactWidth`, `compactHeight` | `180`, `32` | Resting size, in logical px. The height is also what windows keep clear. |
| `bottomRadius`, `filletRadius` | `10`, `10` | The convex bottom-corner radius, and the concave curve where the notch meets the screen edge. |
| `hoverDelay`, `collapseDelay` | `60`, `350` | Milliseconds. |
| `updateCheck` | `true` | Check GitHub for a newer notch and pop down a notice when there is one. |
| `peekOnTrackChange`, `peekDuration` | `true`, `3500` | Widen briefly on a new track. |
| `batteryGlow` | `true` | The battery glow. |
| `glowScale` | `1.0` | Glow reach relative to the resting notch's size (0 to 2.5, at most 80 px). 0 draws no glow. |
| `glowStyle` | `"outline"` | `"outline"` or `"bottom"`. |
| `chargingColor`, `fullColor`, `lowColor` | `#FFB340`, `#30D158`, `#FF453A` | Glow colours. |
| `lowBattery`, `criticalBattery` | `20`, `10` | Percent thresholds, on battery. |
| `greenAbove` | `100` | Charging at or above this percentage already shows the full colour. |
| `batteryPeek` | `true` | Widen to show the charge on plug-in, unplug and low battery. |
| `stayOpen` | `false` | Keep the notch open on its open view. |
| `autoHide` | `false` | The resting notch hides in the screen edge until the pointer reaches it. |
| `windowsToTop` | same as `autoHide` | Whether windows reach the top edge under the notch. |

Widgets are still placed with `omarchy bar move` and `omarchy plugin enable/disable`.
