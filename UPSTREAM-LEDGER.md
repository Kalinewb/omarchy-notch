# Upstream ledger

Every place the notch copies an Omarchy file or depends on the shape of one. After an Omarchy
update, this is the checklist: for each row, was it re-checked, and is the outcome *port*,
*disable the capability*, or *raise the minimum* ([COMPATIBILITY.md](COMPATIBILITY.md)).

- **Installed Omarchy:** 4.5.0-3 (`omarchy-version`, `$OMARCHY_PATH` = `/usr/share/omarchy`).
- **Recorded baseline:** `dev/upstream/upstream.json` says Omarchy **4.0.5-1**, recorded 2026-10-23.
  Nothing has been re-recorded since, so every "same / moved" below is relative to 4.0.5-1.
- **Reviewed:** 2026-11-22, notch 0.3.0, commit 7ac2391.
- Paths are under `$OMARCHY_PATH/shell/` unless they start with `default/` or `bin/`.

## What was actually run on 2026-11-22

`./dev/upstream.sh` (read-only; `--record` was **not** used), against 4.5.0-3:

```
Upstream  recorded against Omarchy 4.0.5-1, this machine runs 4.5.0-3
  Omarchy changed version
  MOVED plugins/menu/Menu.qml
  MOVED plugins/menu/MenuModel.js
  MOVED Ui/ConfirmDialog.qml
  MOVED Ui/Button.qml
  same  Ui/NumberField.qml
  MOVED plugins/bar/Bar.qml
  MOVED plugins/bar/BarModel.js
  MOVED plugins/notifications/Service.qml
  MOVED plugins/notifications/NotificationLogic.js

8 file(s) moved upstream; port them, then ./dev/upstream.sh --record
```

Beyond that script, also run by hand on the same day (plain `diff` / `cmp` / `ls` / `grep`,
read-only): the recorded copies against the installed files for the rows marked "diffed"; that
the installed `NotificationLogic.js` does not exist (`ls plugins/notifications/`); the installed
manifests and entry files of the menu, OSD, notifications and the four pickers; the `osd` and
`notifications` IPC targets; `live.json` existing under `~/.local/state/omarchy/notifications/`;
the menu keybinds in `default/hypr/bindings/utilities.lua`. **No other diff was done and no
behaviour was exercised.** In particular the suites named below were **not** run for this ledger,
and four of them (`menu`, `platform`, `back`, `panels`) are reported failing on this machine (see
COMPATIBILITY.md, Known issues).

"Changed lines" counts are `diff -u` lines starting with `+` or `-` between the recorded copy and
the installed file: a size, not a review.

## Forked or copied files

| Upstream path | What the notch depends on | Local file and change | Covering suite | Fallback | Checked 4.5.0-3 |
|---|---|---|---|---|---|
| `plugins/menu/Menu.qml` | Row, search, submenu and Apps behaviour; sizes of Omarchy's menu card | `menu/NotchMenu.qml`: forked from 4.0.5; no window, scrim or border, notch colours and radius, `closeRequested`, sizes from the notch (header lists every change) | `dev/menu.sh`, `dev/menu-replace.sh`; `dev/lint.sh` lints the installed `Menu.qml` under the fork's name to compute inherited warnings | Menu companion loads the installed `Menu.qml` by URL; setting off or notch away means Omarchy's own menu | **Diffed: moved** (373 changed lines vs recorded 4.0.5). Fork not ported. |
| `plugins/menu/MenuModel.js` | Menu data model | `menu/MenuModel.js`: byte-identical to the recorded 4.0.5 copy (`cmp`) | `dev/menu.sh` | as above | **Diffed: moved** (263 changed lines). Fork is stale. |
| `Ui/ConfirmDialog.qml` | Uninstall confirmation in the menu | `menu/NotchConfirmDialog.qml`: rounded buttons and scrim, no theme colours | no suite names it (reached only through the menu; unverified) | Omarchy's own menu | **Diffed: moved** (4 lines: `Commons.I18n.t("common.cancel")` / `common.confirm` labels). |
| `Ui/Button.qml` | Button look | `NotchButton.qml`: fills follow the notch (header: "one change") | none by name; used throughout settings, so `dev/panels.sh` loads it indirectly (unverified) | The notch's own look is the only look; no stock fallback needed | **Diffed: moved** (36 lines: width from natural label width, press scale, `Style.duration`). |
| `Ui/NumberField.qml` | Number field look | `NotchNumberField.qml` | as above | as above | `dev/upstream.sh`: **same**. |
| `plugins/bar/Bar.qml` | The whole bar: slots, widget hosting, popout handling, `bar-off`, injected properties, layer namespace `omarchy-bar` | `Bar.qml` (6465 lines): started from `omarchy.bar`, full-width strip replaced by the notch | `dev/lint.sh` (allowance recomputed from the installed file), `dev/contract.sh` (runs the real `Bar.qml`), `dev/surface.sh`, and the rest of `dev/check.sh` | Another bar: `omarchy plugin enable omarchy.bar` | **Diffed: moved** (2067 changed lines vs the recorded 2093-line copy; installed is 3222 lines). Never re-ported as a whole. |
| `plugins/bar/BarModel.js` | Layout parsing | `BarModel.js`: byte-identical to the recorded copy | `dev/lint.sh`, `dev/contract.sh` | as above | **Diffed: moved** (622 changed lines). |
| `plugins/osd/OsdModel.js` | Icon choice and payload to state | `osd-model.js`: byte-identical to `dev/upstream/osd/OsdModel.js` (`cmp`). **Not in `dev/upstream.sh`'s file list or `upstream.json`** | `dev/osd.sh` | Omarchy's own OSD card | **Diffed: moved.** 4.5.0-3 adds an `fmt` argument to `stateForShow` so percentages use the display language's digits. The notch's copy lacks it; digits stay Latin. |
| `plugins/osd/Osd.qml` | Registers `IpcHandler { target: "osd" }`; payload shape | Recorded verbatim in `dev/upstream/osd/Osd.qml` for reference; not forked. The companion loads the installed file lazily by URL | `dev/osd.sh` (against `dev/harness/FakeStockOsd.qml`) | Omarchy's own OSD | **Diffed: moved** (recorded copy vs installed differ). The `osd` target is still there (`grep`). |
| `plugins/menu/BarWidget.qml` | The menu button | `companion/kalinewb.notch-menu/BarWidget.qml`: header says copied from 4.0.3; uses `WidgetButton`, `moduleName: "kalinewb.notch-menu"` | `dev/menu-replace.sh` (names it; depth unverified) | Disabling the companion restores `omarchy.menu`'s own button | **Diffed: differs.** 4.5.0-3 uses `BarIconButton`; the companion still uses `WidgetButton` (type still exists in `Ui/`). |
| `plugins/notifications/Service.qml` and `NotificationLogic.js` | **Not copied.** Recorded copies are 4.0.5's old service. The companion runs the installed `Service.qml` unchanged by URL | `dev/upstream/notifications/*` is reference only | n/a for the copy | n/a | **Both reported moved by `dev/upstream.sh`, but `NotificationLogic.js` no longer exists in 4.5.0-3** (`ls`): the entry is dead and the script reports it as moved. `Service.qml` changed by 2221 lines. The record is stale for notifications; the live shape is in the next section. |

## Shape dependencies (nothing copied)

| Upstream structure | What the notch depends on | Local code | Covering suite | Fallback | Checked 4.5.0-3 |
|---|---|---|---|---|---|
| `~/.local/state/omarchy/notifications/live.json` (written by `plugins/notifications/Store.js` / `Service.qml`) | A JSON list of rows (`key`, `ts`, `summary`, `body`, ...), rewritten whole shortly after a card changes; absent for transient, DND-held and code cards | `NotchNotifications.qml`, `notifications.js` | `dev/notifications.sh`, `dev/notifications-interact.sh`, `dev/quiet.sh` | Notch shows nothing; Omarchy's toast is untouched (README: pre-4.5 Omarchy wrote one file per card) | **File exists, parses as a JSON list, and its rows carry `key`, `ts`, `summary`, `body` (field names only; values not read or recorded).** The `Service.qml` line that writes it is at `Service.qml:1288`. Row fields not re-compared. |
| `plugins/notifications/Service.qml` internals | A `ListModel` of rows (`key`, `ts`, ...) and one `PanelWindow` per screen, found **by shape** among the service's children; the `notifications` IPC target (`invokeLast`, `dismissOne`) | `companion/kalinewb.notch-notifications/Service.qml` (2.0.0), `bridge/NotchNotificationsBridge.qml` | `dev/notifications-companion.sh` (against a stand-in under `dev/harness/notifications-companion/`), `dev/notifications-omarchy.sh` (the **installed** service, server cut out) | Toast window stays visible, i.e. Omarchy's own toast | `ListModel`, `PanelWindow` and `target: "notifications"` all present by `grep`. Not exercised. |
| Plugin routing: `omarchy.clonedFrom` | Omarchy sends a source plugin's calls to an enabled plugin whose manifest says `omarchy.clonedFrom: <id>`; enabling it disables the source; `cloneSourceRestores` brings it back | All seven `companion/*/manifest.json`; `bin/notch-companion` (`conflict_id`, `park`); `bin/notch-setup` (`restore_noted`) | `dev/menu-replace.sh`, `dev/osd.sh`, `dev/overlays.sh`, `dev/setup.sh` | `omarchy plugin disable <companion>` restores the source | `clonedFrom` handling present in `services/PluginRegistry.qml` (`grep`). Not exercised. |
| `omarchy.menu` / `omarchy.osd` / `omarchy.notifications` manifests | Ids, kinds (`menu`+`bar-widget`; `panel`; `service`), `keepLoaded` | Companion manifests mirror them (OSD adds `service`) | `dev/osd.sh`, `dev/menu-replace.sh` | as above | Installed manifests read: ids and kinds as expected. |
| `bin/omarchy-osd` -> `omarchy-shell -q osd show <payload>` | The CLI hits the `osd` target directly and never goes through clone resolution, so the companion must own the target as a **service** | `companion/kalinewb.notch-osd/Service.qml` | `dev/osd.sh` | Omarchy's own card, loaded lazily (eager load handed the target back) | Script read: unchanged behaviour. |
| Pickers `plugins/{clipboard,emojis,image-picker,reminders}` | Kind `overlay`; entry `Clipboard.qml`, `Emojis.qml`, `ImagePicker.qml`, `ReminderFlow.qml`; a window holding one card plus passive full-bleed fillers, card centred and sized from the window | `OverlayHosting.qml`, `GuestHosting.qml`, `bridge/NotchOverlayBridge.qml`, four `companion/kalinewb.notch-*/Facade.qml` (one shared file, only `clonedFrom` differs) | `dev/overlays.sh` (parts A to D, part A against the installed pickers) | Only the four ids are offered; a mismatch is declined and the picker maps its own window | Manifests and entry files present. Card structure not re-inspected. |
| Panel structure: `Ui/KeyboardPanel`, `Ui/PanelController`, `Ui/Panel` | `contentItem`, `focusTarget`, `ensureContent` (lazy `content:` since 4.5); `open: root.opened`; widget root or one `Loader` deep | `PanelHosting.qml`, `GuestHosting.qml` | `dev/hosting.sh` (against the installed audio panel `plugins/panels/audio/Panel.qml`), `dev/overlays.sh` | Declined with a reason; plugin keeps its own window | Types present in `Ui/`; `focusTarget` property present in `KeyboardPanel.qml`. Not exercised. |
| Bar layout and `bar-off` | `bar:` in `shell.json`; `~/.local/state/omarchy/toggles/bar-off` flag; `omarchy-toggle-bar` then `omarchy-shell -q omarchy.bar syncHidden`; layer namespace `omarchy-bar` for Omarchy's `no_anim` rule | `Bar.qml`, `bin/notch-setup` (`detect_bar_off`, `detect_layer_rules`) | `dev/setup.sh` (`bar-off`, layer rules); `dev/surface.sh`, `dev/menu.sh` (namespace / `no_anim`) | Another bar | `omarchy-toggle-bar` read: as described. |
| Keybind runtime behaviour | Hyprland keeps runtime binds across a shell restart; `hyprctl binds -j`; `hyprctl eval` for binds and layer rules (Lua config); Omarchy's menu keys in `default/hypr/bindings/utilities.lua` | `bin/notch-keybinds`, `bin/notch-setup-binds.lua`, `bin/notch-setup` (`detect_menu_keys_bypass`) | `dev/keys.sh`, `dev/setup.sh` (fixtures `utilities-command.lua` for pre-4.5, `utilities-table.lua` for 4.5) | A key that cannot be added is reported by Setup; Omarchy's own keys are untouched | `utilities.lua` read: the 4.5 table form (`{ menu = "root" }`). `hyprctl` runtime behaviour not re-checked. |
| Plugin manager CLI | `omarchy plugin add / update / remove / validate / enable / list --json`; plugins folder `~/.config/omarchy/plugins` | `bin/notch-update`, `bin/notch-plugins`, `bin/notch-companion`, `install.sh` | `dev/update.sh`, `dev/plugins.sh`, `dev/menu-replace.sh` | Run the commands by hand | `omarchy plugin list --json` run on this machine: works. Others not run. |

## Gaps in the record itself

- `dev/upstream.sh`'s file list omits the OSD copy, the menu `BarWidget.qml`, and every shape row
  above. `upstream.json` is 4.0.5-1 and still names a file that no longer exists upstream.
- `dev/upstream.sh` exits 1 with 8 moved files, which is the correct signal, but nothing makes a
  release depend on it (COMPATIBILITY.md, "What does not exist yet").
- Nothing records, per row, who reviewed a move and what they decided. The outcome column in this
  table is the first attempt at that and is a snapshot of 2026-11-22, not a commitment.
