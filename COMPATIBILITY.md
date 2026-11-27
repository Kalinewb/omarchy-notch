# Compatibility

What the notch has been checked against, what each capability needs from Omarchy, and what the
user gets when it cannot work. Every row is stated from the code in this repository and the
Omarchy installed on the maintainer's machine; where a claim was not checked it says
**unverified**. The per-file detail behind the rows is in [UPSTREAM-LEDGER.md](UPSTREAM-LEDGER.md).

Last reviewed: 2026-11-22, notch 0.3.0 (`manifest.json`), commit 7ac2391.

## Versions

| | Version | How it was established |
|---|---|---|
| Omarchy (installed, reviewed against) | 4.5.0-3 | `omarchy-version`, `pacman -Q omarchy` on 2026-11-22 |
| Hyprland | 0.56.2 | `hyprctl version` (package `hyprland 0.56.2-4`) |
| Quickshell | 0.3.2 (package `0.3.2.r7.g2b4501a-1`, distributed by Omarchy) | `quickshell --version` |
| Omarchy the forked files were ported from | 4.0.5-1 | `dev/upstream/upstream.json`, recorded 2026-10-23 |
| Omarchy the notifications companion targets | 4.5 and newer | README, `companion/kalinewb.notch-notifications/Service.qml` |

**The notch declares no supported range.** `manifest.json` has no Omarchy version field and
nothing at install time refuses an unsupported Omarchy. The range below is what the repository
shows it was written and tested against, not a guarantee:

- It was ported from 4.0.5 and still carries 4.0.5 copies of the menu, the bar, the confirm
  dialog and a button (see the ledger).
- Several 4.5 adaptations exist in the history (the notification live file, the companion's
  toast discovery, lazy panel content, the menu key table in Setup) and their fixtures describe
  both the pre-4.5 and the 4.5 shape.
- **Full-suite status on 4.5.0-3 is not established.** See Known issues. "Last checked against
  4.5.0-3" in this document means "the capability shapes below were read against the installed
  4.5.0-3 files on 2026-11-22", not "`./dev/check.sh` passed on 4.5.0-3".

Hyprland and Quickshell have no recorded minimum either. The notch uses `hyprctl eval` to add
keybinds and layer rules at runtime (`Bar.qml`, `bin/notch-keybinds`), which needs a
Lua-configured Hyprland (`bin/notch-setup-binds.lua` reads the user's `hyprland.lua`); the
oldest Hyprland and Quickshell that work are **unverified**.

## Capabilities

"Min Omarchy" is the oldest release the capability is documented or coded to need. "Not
declared" means nothing in the repository states one.

| Capability | Min Omarchy | Depends on in Omarchy | Stock fallback when it cannot work |
|---|---|---|---|
| **The notch as the bar** (centred bar, widget hosting, bar layout) | Not declared (forked from 4.0.5) | `bar` plugin kind and its injected properties (`omarchyPath`, `barWidgetRegistry`, `pluginRegistry`, `barConfig`, `shell`); `bar:` subtree of `~/.config/omarchy/shell.json` (`id`, `position`, `layout`); `qs.Commons` / `qs.Ui` singletons and types; the `bar-off` toggle file in `~/.local/state/omarchy/toggles/` written by `omarchy-toggle-bar`; layer namespace `omarchy-bar` for Omarchy's own `no_anim` layer rule | `omarchy plugin enable omarchy.bar` (or `omarchy plugin remove kalinewb.notch`). A QML load error makes a third-party plugin silently absent, which is why `dev/lint.sh` gates install. |
| **Hosting unmodified `KeyboardPanel` panels** (Audio, Wifi, Bluetooth, clock, Profiles, Face ID, ...) | Not declared. Handles both eager panel content and 4.5's lazy `content:` Component (`PanelHosting.qml`, `ensureContent`) | `Ui/KeyboardPanel` (`contentItem`, `focusTarget`, `ensureContent`), `Ui/PanelController`, the `open: root.opened` binding of `Ui/Panel`; the widget's panel at most one `Loader` deep (SURFACE-HOSTING.md section 11) | Declined with a reason (`no widget`, `no panel`, `panel has nothing in it`, `no panel controller`); the plugin keeps its own window. Off by default per widget (`hostedPanels`), switch in Settings -> Advanced -> Panels. Best effort: an Omarchy change to those types can break it without a version signal. |
| **Native integrations, contract 1** | None Omarchy-side identified | Plugin manifest `surface: { "contract": 1 }` and `entryPoints.surface` (SURFACE-HOSTING.md section 1); the notch accepts contracts 1 to 1 (`platform.js`: `CONTRACT = 1`) | `contract-newer` / `contract-older` / declined: the plugin stays standalone with its own window. Switch off per plugin in Settings -> Advanced -> Panels. |
| **Menu replacement** ("Menu") | Not declared (forked from 4.0.5; 4.5's menu keys are handled in Setup) | `omarchy.menu` plugin (`menu` + `bar-widget` kinds); Omarchy's `clonedFrom` routing (`services/PluginRegistry.qml`); `$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc` and `~/.config/omarchy/extensions/omarchy-menu.jsonc`; `omarchy-menu*` scripts; the menu keybinds in `default/hypr/bindings/utilities.lua` (a command before 4.5, a `{ menu = "root" }` table since) | The companion's go-between loads Omarchy's own `plugins/menu/Menu.qml` from `$OMARCHY_PATH` whenever the notch is not running, is hidden, is not the bar, or the setting is off. A picker caller is released rather than left waiting. Off-switch: `omarchy plugin disable kalinewb.notch-menu`. |
| **OSD** ("Volume and brightness") | Not declared. Verified present on 4.5.0-3: `omarchy-osd` calls `omarchy-shell -q osd show <payload>`; `omarchy.osd` registers `IpcHandler { target: "osd" }` | `omarchy.osd` plugin and its `osd` IPC target; payload `{icon, message, value, max, progressText, duration}`; `osd-model.js` is a copy of Omarchy's `OsdModel.js` as of 4.0.5 | The notch answers `shown` or `declined:<reason>`; anything else shows Omarchy's own card (panel open, bar hidden, no notch). Off-switch: `omarchy plugin disable kalinewb.notch-osd`. |
| **Notifications** (toast mirrored in the notch; "Suppress Omarchy's own toast") | **4.5** (README; stated again in `notifications.js` and the companion) | `~/.local/state/omarchy/notifications/live.json` (rows with `key`, `ts`, ...; verified present on 4.5.0-3); the `omarchy.notifications` service's `ListModel` of rows and one `PanelWindow` per screen, found **by shape**; its `notifications` IPC target (`invokeLast`, `dismissOne`). Omarchy's `Service.qml` runs unchanged from `$OMARCHY_PATH` | On an older Omarchy the notch shows nothing and Omarchy's toast is untouched. On 4.5+, Omarchy's toast is back whenever the notch cannot show a card (no notch, bar hidden, setting off, restored or replayed toast, verification-code card, burst overflow). If nothing owns `org.freedesktop.Notifications`, "Notch only" switches itself off. Off-switch: `omarchy plugin disable kalinewb.notch-notifications`. |
| **Pickers**: clipboard, emojis, image picker, reminders | Not declared | `omarchy.clipboard`, `.emojis`, `.image-picker`, `.reminders` (kind `overlay`); each plugin's window holding a card plus passive full-bleed fillers (`OverlayHosting.qml` header lists the assumptions); their entry files `Clipboard.qml`, `Emojis.qml`, `ImagePicker.qml`, `ReminderFlow.qml` (the go-between's `stockFiles` table, verified present on 4.5.0-3) | Only these four ids are ever offered; anything not matching is declined and the picker maps its own window. Opt-in per picker (`hostedPanels`, Settings -> Advanced -> Panels); off by default. Off-switch: `omarchy plugin disable kalinewb.notch-<picker>`. |
| **Plugins page and catalogue** | Not declared | `omarchy plugin add / update / remove / validate / enable / list --json`; the plugins folder `~/.config/omarchy/plugins` (fixed, never `XDG_CONFIG_HOME`); `systemd-run --user`; `plugins/catalogue.json` pins (full commits) | Without the notch, each plugin installs from its own README with `omarchy plugin add <url>`, which installs HEAD, not the pinned commit. |
| **Setup / "Needs attention" and repair** | Not declared | `hyprctl binds -j`, `hyprctl configerrors -j`, `hyprctl eval`; `lua` (reads the user's Hyprland config with a recording `hl` stand-in); `omarchy-version`, `omarchy-shell`, `omarchy-hyprland-session-locked`; `shell.json` (`cloneSourceRestores`) | Setup only reads unless the user presses a fix; every fix is snapshotted and undoable. A check that cannot decide reports "unknown" and shows nothing. |
| **Config import / export** | Not declared | The notch's own `bar.notch` keys in `shell.json`; Setup snapshots | Preview before apply; **Undo** restores the snapshot. No Omarchy dependency beyond `shell.json`. |
| **Updates** (check, update, restart) | Not declared | A git checkout of the plugin (`omarchy plugin add`); `omarchy plugin update kalinewb.notch --yes`; `omarchy restart shell`; `systemd-run --user` | `updateCheck: false` turns checking off; a failed update shows why until dismissed; `omarchy plugin update kalinewb.notch` works from a terminal. |

## What does not exist yet

- No `dev/compat.sh`. The only upstream drift check is `dev/upstream.sh` (and Setup's
  `upstream-drift` point, which uses the same record). Neither fails a release.
- No minimum-version enforcement anywhere: the notch does not read `omarchy-version` to decide
  whether a capability is allowed. The notifications capability degrades because the 4.5 file and
  window shapes are not found, not because a version was compared.
- No automated or recorded live-session smoke run on a named Omarchy release.

## Known issues

- **Four suites currently fail against Omarchy 4.5.0-3 on the maintainer's machine: `menu`,
  `platform`, `back` and `panels`.** This was reported by the maintainer and **was
  not re-run while writing it**; the cause of each is not established here. Another contributor is
  fixing them. Do not read this document as saying the suites pass.
  Placeholder, to be replaced when the fix lands: `TODO(update): <date>, commit <sha>, suites
  menu/platform/back/panels <pass|fail>, Omarchy <version>`.
- `dev/upstream.sh` reports **8 of 9** recorded files moved against 4.5.0-3, and one of them
  (`plugins/notifications/NotificationLogic.js`) no longer exists upstream. Details and the
  command output are in the ledger. The menu fork (`menu/NotchMenu.qml`) has not been ported past
  4.0.5.
- README says "Omarchy 4.0.5's `Menu.qml`", which is the recorded baseline, not the installed
  version.

## Updating this document

After an Omarchy (or Hyprland / Quickshell) update: run `./dev/upstream.sh`, `./dev/check.sh`,
record the result under Known issues or in the ledger, and change the "Last reviewed" line only
for what was actually run. Raising a capability's minimum, disabling it, or porting the fork are
the three honest outcomes of a moved file.
