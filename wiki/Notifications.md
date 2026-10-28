# Notifications

Omarchy's toasts, and its volume and brightness card, shown in the notch instead of (or as well as) where Omarchy puts them.

Both depend on a small companion plugin, installed by the notch itself when you switch the matching setting on. Each companion says it is a clone of an Omarchy plugin (`clonedFrom`), so Omarchy loads it instead of its own, and each one falls back on Omarchy's own behaviour whenever the notch cannot do the job. Turning the setting off, or disabling the companion with `omarchy plugin disable <id>`, puts Omarchy's own back exactly.

## Notifications

*In the notch.* Three choices (`notifications`, `suppressNativeToast`):

- **Notch + toast** (the default): a toast also shows in the notch, with its glyph and summary on the resting row and the body wrapped underneath (up to two rows, elided after that), the notch widening and growing down to fit. Omarchy's own toast still appears too.
- **Notch only**: the notch is the only place a toast shows.
- **Off**: nothing in the notch.

The notch finds a toast by watching the folder Omarchy writes one file per live toast into, `~/.local/state/omarchy/notifications`. It never owns the notification bus, never closes a notification itself and never touches Do Not Disturb.

**Notch only needs the notifications companion** (`kalinewb.notch-notifications`, the folder in `companion/`). It says `clonedFrom: omarchy.notifications`, so Omarchy loads it instead of its own. It runs Omarchy's real `Service.qml`, unchanged, from `$OMARCHY_PATH`, so the notification server, Do Not Disturb, history and the `notifications` IPC target are all Omarchy's own code. The only thing it changes is whether the toast window is visible. Nothing on disk is patched, which is what makes it work on a packaged install, where `$OMARCHY_PATH` belongs to root.

**A notification is never shown nowhere.** Omarchy's toast is back whenever the notch can't show it: no notch running, the bar hidden, the notch's notifications off, a toast the notch wouldn't show anyway (one restored after a shell restart, or your notification history replayed on request), or one it hasn't drawn yet (in a burst, the fifth waits for a free line, and Omarchy's toast stays until it has one).

**Click it like Omarchy's own.** Left click opens the notification (its default action, or its app), right click dismisses it. Both are Omarchy's own calls, not a copy of what they do: through the companion, straight into Omarchy's service for that toast; without it, through the `notifications` IPC target Omarchy's keybinds use (`invokeLast`, `dismissOne`). Pointing at it does not turn the notch into its hover view, and holds its clock while the pointer is on it.

**To undo:** pick *Notch + toast* or *Off* (Omarchy's toast is back at once), or `omarchy plugin disable kalinewb.notch-notifications`, which puts `omarchy.notifications` back exactly.

If the companion is switched off, not running or not installed, [Setup](Setup-points.md#the-notifications-companion-is-switched-off) says so. A companion that is enabled but not loaded matters most: it stands in for Omarchy's service, so nothing may be showing notifications at all.

## Notification light

*In the notch.* **Off** (the default), **Around the notch**, **Top edge** or **Full screen**: a light drawn while a notification shows, stored as `notificationLight`.

**Coming.** The row is in the panel and saves the setting, but the light itself is not built, so nothing reads the setting yet and choosing a style changes nothing on screen. This page will say how each style looks when it exists.

## Volume and brightness

*In the notch.* Omarchy answers a volume key, a brightness key or a media button with a card at the bottom of the screen. With this switched on (`replaceOsd`) the notch shows it instead: one row (the glyph, a bar and the readout, or the word) with the notch widening around it and shrinking back. The glyph and the readout are Omarchy's own (`osd-model.js` is its model, vendored), so *volume-muted* is the glyph Omarchy picks; the drawing is the notch's, so there is no card, no theme colour and no accent on the bar.

- **It needs the same kind of one-time set-up as the menu**, and does it itself: a small companion plugin (`kalinewb.notch-osd`, the folder in `companion/`). Omarchy routes an OSD call to whichever plugin says `clonedFrom: omarchy.osd`; the companion's go-between asks the notch first and falls back to Omarchy's own card, loaded from `$OMARCHY_PATH`, so nothing is a copy.
- **A key press never does nothing.** The notch answers `shown` or `declined:<reason>`, and anything but `shown` shows Omarchy's own card: with a panel open (it would cover what you opened), with the bar hidden, or with no notch running. Neither display is ever left up under the other.
- **It outranks a peek and yields to a panel.** An OSD answers a key you just pressed; a peek is the notch volunteering something.
- **To undo:** turn the switch off, or `omarchy plugin disable kalinewb.notch-osd` from a terminal, which puts `omarchy.osd` back exactly.
- Over IPC: `omarchy-shell notch osd '<payload>'` takes Omarchy's own payload (`{icon, message, value, max, progressText, duration}`) and answers `shown` or why not; `omarchy-shell notch osdClose` takes it down. `dev/osd.sh` tests the lot, with the notch and the companion laid out the way the plugins folder is.

[Setup](Setup-points.md#the-osd-companion-is-switched-off) reports a companion that is off or missing.

## Notification time

*Advanced.* How long the notch's copy of a toast stays: **Until I act**, or a number of seconds (3, 6, 10 or 30 in the row; 1 to 60 by hand, 6 by default). The notch's copy keeps its own time, so it outlives Omarchy's own toast when that ends first; one whose toast has ended can still be opened (its action runs, or its app is focused) or dismissed. The row is dimmed while notifications are off.

## Light colours

*Advanced.* **Aurora** (the default), **Blue** or **White**, stored as `notificationLightColours`. The row is dimmed while *Notification light* is off. As with that row, this is stored and not yet drawn.

## Peeks

A peek is the notch volunteering something rather than answering a toast or a key: a new track, a charger going in or out, a low battery. It shows that one thing for a few seconds. They are the *Peeks* row in [Settings](Settings.md#peeks).
