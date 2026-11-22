# Companions

A companion is a small separate plugin in `companion/<id>/` that lets the notch stand in for one
of Omarchy's own surfaces. Its manifest says `omarchy.clonedFrom: <omarchy id>`; Omarchy then
sends that plugin's calls to the companion instead, and the companion's go-between asks the notch
first and **falls back to Omarchy's own implementation, loaded by URL from `$OMARCHY_PATH`**, when
the notch declines. Nothing in Omarchy is patched and nothing is a copy of Omarchy's code.

The notch is one plugin; each companion is its own plugin folder under
`~/.config/omarchy/plugins/`, installed only when a setting needs it. For what each one needs from
Omarchy, see [COMPATIBILITY.md](../COMPATIBILITY.md) and [UPSTREAM-LEDGER.md](../UPSTREAM-LEDGER.md).

| Companion id | Owner feature (setting) | Stands in for | Source (`companion/`) | Stock fallback |
|---|---|---|---|---|
| `kalinewb.notch-menu` | Replace the Omarchy menu (`replaceMenu`) | `omarchy.menu` | `kalinewb.notch-menu/` (`Facade.qml`, `BarWidget.qml`) | Omarchy's `plugins/menu/Menu.qml` |
| `kalinewb.notch-osd` | Show the OSD in the notch (`replaceOsd`) | `omarchy.osd` | `kalinewb.notch-osd/` (`Facade.qml`, `Service.qml`) | Omarchy's `plugins/osd/Osd.qml`, loaded only when needed |
| `kalinewb.notch-notifications` | Suppress Omarchy's own toast (`suppressNativeToast`; also needs `notifications` on) | `omarchy.notifications` | `kalinewb.notch-notifications/` (`Service.qml`) | Omarchy's real `Service.qml` runs unchanged; only its toast windows are hidden, and they come back whenever the notch will not show a card |
| `kalinewb.notch-clipboard` | Clipboard opens in the notch (id `omarchy.clipboard` in `hostedPanels`, Settings -> Integrations) | `omarchy.clipboard` | `kalinewb.notch-clipboard/` (`Facade.qml`) | Omarchy's `plugins/clipboard/Clipboard.qml` |
| `kalinewb.notch-emojis` | same, `omarchy.emojis` | `omarchy.emojis` | `kalinewb.notch-emojis/` | `plugins/emojis/Emojis.qml` |
| `kalinewb.notch-image-picker` | same, `omarchy.image-picker` | `omarchy.image-picker` | `kalinewb.notch-image-picker/` | `plugins/image-picker/ImagePicker.qml` |
| `kalinewb.notch-reminders` | same, `omarchy.reminders` | `omarchy.reminders` | `kalinewb.notch-reminders/` | `plugins/reminders/ReminderFlow.qml` |

The four picker `Facade.qml` files are identical except for the comment naming the picker; which
picker one stands in for comes from its manifest's `clonedFrom`. All of this is from `Bar.qml`
(the `Companion` instances and `overlayCompanionSpecs`), `Companion.qml` and the manifests.

## How it is installed and kept in step

**From the notch (normal path).** Turning the setting on is the whole user action. `Companion.qml`
reads the folder's state (`bin/notch-companion status`): `absent`, `disabled`, `outdated` (files or
API version differ from the notch's own copy) or `active`. While the setting is on, it starts one
detached job per state it finds: `install` for absent or disabled, `sync` for outdated. A failed job
is not retried until the setting is switched off and on again, or the notch restarts, and Needs
attention reports it (menu, OSD and notifications only; there is **no Setup point for the four
pickers**). Jobs run in their own `systemd-run --user` unit because copying into the plugins folder
reloads every plugin and destroys the notch that started it, and report through a status file in
`$XDG_RUNTIME_DIR/kalinewb.notch/companion*.json`.

`bin/notch-companion install` refuses while the session is locked, or when another enabled plugin
already says `clonedFrom` the same id. Otherwise it copies the folder (staged under a dot-name,
validated with `omarchy plugin validate`, refused if it contains symlinks), moves it into
`~/.config/omarchy/plugins/<id>`, waits up to 10 s for the shell to see it, and runs
`omarchy plugin enable <id>`. If the shell does not see it in time, or enabling fails, the job ends
"Installed" with the command to run by hand. Enabling a clone makes Omarchy disable its source;
the menu companion also swaps the `omarchy.menu` button in the bar layout for its identical one.

**`install.sh` (development).** After it fast-forwards the live checkout and the shell is allowed to
restart (it does nothing to companions while the session is locked), it loops over the seven
companions. For each one that is **already installed** and has a folder in the live checkout's
`companion/`, it runs this repo's `bin/notch-companion sync --from <live checkout>/companion/<id>`.
Companions that are not installed are skipped. The copy comes from the fast-forwarded live checkout,
never from the working tree. `sync` returns success when the files already match, so `install.sh`
prints `synced <id>` either way; the job's own message says "already up to date". When a sync
replaces a folder, the old one is moved to
`~/.local/state/kalinewb.notch/backups/<UTC stamp>-notch-menu` (the suffix is the same for every
companion; see "Contradictions" below).

## Enable, disable, remove

| You want | Do | Result |
|---|---|---|
| Stop using it, keep it installed | Switch the setting off | The companion stays installed and enabled; its go-between hands every call to Omarchy's own implementation, so behaviour is stock. It is **not** removed or disabled automatically. |
| Put Omarchy's own back at the plugin level | `omarchy plugin disable <id>` | Re-enables the source exactly as it was (README). The notch's next `keepInStep` will enable it again only while the setting is still on. |
| Remove it for good | `omarchy plugin remove <id>` | Source is restored. `bin/notch-companion remove <status file>` wraps the same command (`--yes`), but no button in the notch calls it (`grep`: `Companion.remove()` has no caller). |
| Remove the notch | `omarchy plugin remove kalinewb.notch` | `omarchy.bar` returns. Companions are separate folders and **stay** (README). Each go-between reaches the notch through a bridge loaded from the notch's folder; a missing notch just means the stock implementation (stated in each `Facade.qml` / `Service.qml` header; not exercised for this document). |
| Switch to another bar | `omarchy plugin enable <bar id>` | Only the notifications companion is switched off for you: `Bar.qml` calls `notch-companion park` as the notch is destroyed, and it disables the companion only if `shell.json` no longer names the notch as the bar. The menu, OSD and picker companions are left as they are and fall back on their own because no notch answers. Coming back, the notch switches the notifications companion on again if the setting is on. |

## What the user can see

Settings shows one status per companion: `working`, `failed`, `absent`, `disabled`, `outdated`,
`hidden-bar` (setting on while the bar is hidden: the stock implementation is showing),
`active-on` or `active-off`. Anything the notch cannot show is shown by Omarchy's own surface, so a
request is never dropped; a picker's caller is released if no menu can take it.

## Contradictions found while writing this

These are in the code or its comments, not fixed here (documentation-only change):

- `bin/notch-companion` names every backup `...-notch-menu`, whichever companion it is (the
  `mv` in `sync_files`).
- Its header comment still describes two or three companions (menu, OSD, notifications); there are
  seven, and its `LABEL` default covers only OSD, notifications and "menu" (the notch passes
  the label for the rest).
- `bin/notch-companion install` fails with "<id> already replaces Omarchy's menu." for a conflict
  on any companion, not only the menu.
- `README.md` says the notch installs three companions; the picker companions are a fourth to
  seventh and are installed by `hostedPanels`, which the README does not describe (it is in
  `SURFACE-HOSTING.md` and `dev/own-window-hosting.md`).
