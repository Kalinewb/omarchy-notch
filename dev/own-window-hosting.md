# Plugins that open in a window of their own: getting them into the notch

Branch `own-window-hosting` (from `notch-all` 8d22bf3). Companion to the
plugins-in-notch audit (kept outside this repository), which lists which plugins
open as a window and why the notch's panel hosting (`PanelHosting.qml`) cannot take
them: it needs a `KeyboardPanel` and a `PanelController`, and these have a raw
`PanelWindow`, `FloatingWindow` or `OverlayWindow` and neither.

The rule they are measured against (the user's, `ui-single-back-control`): one
visible way back, the notch's top-middle strip, whose hit area is the whole zone;
Esc is an invisible alias; no panel-drawn back button or "esc goes back" hint;
content keeps out of the zone; back from a plugin's first page returns to where the
notch was, not just closes.

## What the platform allows (checked, not assumed)

1. **The notch cannot reach another plugin's items.** A bar widget is built by the
   notch itself, so `widgetItemFor()` has it. A panel or overlay plugin is built by
   the shell's own `Loader` (`shell.qml`, `panelLoaders`), a non-visual `Loader`
   with no parent, and the notch (third-party, so it is given the scoped
   `PluginShellApi`) gets only `summon / hide / toggle / isPluginOpen` for ids it
   may control. There is no `panelLoaders`, no registry of live items, and
   `Commons.IpcRegistry` holds IPC handlers, not their owners. So *nothing the
   notch does from the outside can find a window-based plugin's content*.
2. **A plugin that the notch builds, it can host.** That is why the three companions
   already work: Omarchy routes every `omarchy.menu` / `.osd` / `.notifications` call
   to an enabled plugin whose manifest says `omarchy.clonedFrom: <id>`
   (`PluginRegistry.resolveEnabledId`), and enabling the clone puts the source in
   `disabledPlugins`. The clone's entry point loads the stock file by URL from
   `$OMARCHY_PATH` (so it is the real thing and follows Omarchy), and reaches the
   notch through a bridge singleton. Nothing in `resolveEnabledId`, `setEnabled` or
   the disabled-list handling restricts `clonedFrom` to first-party sources.
3. **A window can be held down without knowing how the plugin maps it.** A Qt
   `Binding { property: "visible"; value: false; when: ... }` overrides whatever
   binding or assignment the plugin has, redirects the plugin's own writes, and
   restores the plugin's own binding when it ends. Probed on Omarchy's real emoji
   picker: the window never maps, `shown`/`opened` stay true (the plugin is *told*
   it is open and runs its open-time code), and `implicitWidth/Height` can be given
   by a second pair of Bindings, which is what lets the card size itself (it reads
   `panel.width`) in a window that never maps.
4. **What a picker's window holds is a card plus passive fillers.** The four Omarchy
   pickers each hold a full-bleed scrim `Rectangle`, a full-bleed click-outside
   `MouseArea` and one card (a `BorderSurface` or an `Item`) that centres itself and
   sizes itself from the window. Taking the card and leaving the fillers is all the
   moving there is. (The image picker also has a second non-card child, a delete
   confirmation, that travels with the card.)

## Decision, class by class

### (a) First-party pickers: clipboard, emojis, image picker, reminders — **built**

Mechanism: an *adapter* (`OverlayHosting.qml`) plus a *clone companion* per picker
(`companion/kalinewb.notch-clipboard|emojis|image-picker|reminders`) plus a *bridge*
(`bridge/NotchOverlayBridge.qml`). Not a synthetic `PanelController`: the plugin has
no controller to make the notch's existing code react to, and inventing one would be
a fiction about the plugin's state. The adapter moves what is real.

```
keybind / omarchy-menu / shell summon omarchy.emojis
   -> Omarchy resolves to kalinewb.notch-emojis (clonedFrom), keepLoaded, entry = Facade.qml
   -> Facade.open(payload)
        notch wants it? (bar.notch.hostedPanels, notch on screen)
          no  -> stock picker opens in its own window, unmodified (the fallback is the stock file)
          yes -> arm  (Binding: window visible=false, implicitWidth/Height = notch's max panel area)
                 stock.open(payload)           the picker runs its own code, believes it is open
                 host -> Bar.hostPanel -> openHosted: pushState(), take(card -> hostedSlot)
   Esc (the picker's own handler)  -> opened=false -> Facade -> notch.release -> goBack()
   back strip                      -> goBack -> closePanels -> hostedReturn -> giveBack:
                                      card back to its window, picker.close(), hold released
```

* **Same hosted slot, same view, same strip.** The picker's card lands in
  `hostedSlot` and the notch's `view = "hosted"`. Back, history (`viewStack`),
  quiet, focus, growth spring, fade timings are the existing ones. Bar.qml's reads
  of `root.hosting` now go through `GuestHosting.qml`, which answers for whichever
  of `PanelHosting` (bar widgets) or `OverlayHosting` (pickers) holds the slot.
* **Opt-in, off by default,** in the list that already holds the widgets' panels,
  `bar.notch.hostedPanels`: a picker's Omarchy id there (`omarchy.emojis`) is the
  user asking for it, read as the four the adapter has been proven on and nothing
  else. No new setting key, so nothing else that counts the notch's keys changes
  (`dev/settings.sh` decides every key the notch reads), and the Integrations toggles
  leave the pickers' entries alone. The
  companion for a picker is installed and kept in step by the existing `Companion`
  machinery (`bin/notch-companion`, one folder per clone, synced by `install.sh`)
  only while its picker is on; off means Omarchy's own picker, untouched.
* **No plugin file is modified.** The stock file is loaded read-only by URL. The
  only things changed in it while hosted are `visible`, `implicitWidth/Height` of its
  window, and (to avoid a second, lighter card inside the notch's black) the card's
  `color` and `border.width`, all by `Binding`s that Qt restores.
* **The bridge is as private as the other three** (SURFACE-HOSTING.md section 12). Its
  api answers only for the four ids in `overlayHostable`, and only when the user turned
  that picker on; it does not check that the item it is handed *is* that picker, so a
  plugin that loads the connector could hand it something else. That is the same trust
  as the menu companion's, and the reason it is not documented as an extension point.
* **Colours.** A hosted *panel* is drawn through the notch's mono shader. A picker
  is its content (an emoji, a wallpaper thumbnail), so `monochrome` is false for an
  overlay and the slot's layer is off.
* **A picker that opens late** (the image picker scans a folder first) is held from
  the start and taken when it reports `opened`; one that never opens leaves only a
  hold that the next summons replaces.

UI-rule status of what is built: no own back control exists in these pickers (they
have Esc only, no hint); the strip is the one back control; Esc is the picker's own
handler and goes through `goBack()` (so a picker opened from the menu returns to the
menu: tested). A picker is not pushed down for the strip: its card sits at the
notch's side padding like any hosted panel (the strip is a keep-clear zone at the top
centre, not a shelf; SURFACE-HOSTING.md section 15). `dev/overlays.sh` checks that no
control of the card is in the zone; the pickers' text is Omarchy's own layout and is
not checked or changed (a search placeholder that runs under the zone is the same
accepted collision as a third-party panel's centred title). **Not done here, deliberately:** a Settings → Integrations row (the
setting is written by `notch overlayHostingSetting <id> on|off` and the same key).

### (a') Other first-party own-window plugins: wifiqr, speedtest, disk-speedtest, dev-gallery — **not built**

The route is the same (they are loaded by the shell, so a clone could front them)
but the adapter's filter is not: `wifiqr` puts its scrim `Rectangle` *with* a
click-catcher child and its content in a full-bleed `keyCatcher` (so "a filler holds
nothing" would take the scrim into the notch), `speedtest` is a scrim with no card
(dials designed for the whole screen), and `dev-gallery` is a `FloatingWindow` of
1855 lines for developers. Each needs a decision about *what part is the card*, which
is per-plugin knowledge and which should be proven against the real file before
being offered (as the four were). wifiqr is also a Wi-Fi password QR: a screen-wide
dark scrim is part of how it is meant to be read.

### (b) Third-party windows: omaland, arcdock settings, voxtype settings, keybindings, spotify

**Embedding their content cannot be done without the plugin's cooperation or a
per-plugin wrapper, and neither is built.** Facts, from the files on this machine:

| plugin | window | summons | what is in the way |
|---|---|---|---|
| `bobbynicholas.omaland` | raw `PanelWindow` (namespace `omaland`), scrim + centred card | `shell toggle` | needs its `service` injected; own `x` button and "Esc close" hint |
| `io.github.claudsondouglas.arcdock` settings | raw `PanelWindow` (`arc-dock-settings`) | `shell toggle` | same file as the dock service; own `x`, Esc hints |
| `io.voxtype.settings` | raw `PanelWindow` (`voxtype-settings`), versioned folder `1.2.1/` | `shell toggle`, keepLoaded | own `x` in the title row |
| `ming.keybindings` | `FloatingWindow` "Keybindings" 1040 x 640 (an xdg toplevel, not a layer) | `shell toggle` | sets `window.visible` imperatively; the cleanest candidate |
| `quickshell.spotify` | mini popup is a `KeyboardPanel` with no `PanelController`; full panel a `FloatingWindow` | its IPC (**controls playback**) | own `󰁍` Back, close button, "Esc to close" line |

Ranked options, in the order they should be taken:

1. **The plugin integrates** (`entryPoints.surface`, SURFACE-HOSTING.md): its panel is
   written for the notch and honours the rule (no back button, inset, `goBackInside`).
   This is the supported route and the only one that can satisfy "no own back
   controls": these plugins *draw* their own `x`, `Back` and Esc hints, and a host
   cannot remove drawn controls from someone else's card without modifying it.
2. **A clone-wrap companion per plugin**, the mechanism of (a) applied to a third-party
   id. Mechanically supported (point 2 above), the adapter looks for any
   window by shape and should take a `FloatingWindow` the same way (not tried), and
   keybindings would be the proving case. It is not built because: it disables the user's plugin
   in `shell.json` (`disabledPlugins`) and pins the clone to that plugin's file layout
   and injected services (`service`, versioned folders), so it breaks silently when
   the plugin updates; and it would host the drawn `x`/Back/hint, i.e. fail the UI
   rule. A companion that *looks* hosted while showing a second back control is the
   thing the rule was written against.
3. **Window placement with the notch's back semantics** (xdg toplevels only:
   keybindings and spotify's full panel): a Hyprland window rule to place the window
   centred under the notch, and the notch reading `Hyprland.toplevels` to show a card
   or title in itself while it is open, with the strip sending the window its
   close. Layer-shell windows (omaland, arcdock settings, voxtype settings) cannot be
   moved by a rule (`layerrule` has no position), and their only observable is
   `hyprctl layers`, which has no QML API. This gives "appears under the notch", not
   "is inside the notch", and it still leaves each plugin's own back controls. Not
   built: it is a second subsystem and a half-answer.
4. **Leave them as windows**, listed in Setup as "opens in its own window", with the
   reason. This is the honest state of these five today.

Recommendation: ask the authors for (1), and build (2) or (3) only for a plugin the
user names, because each is per-plugin and each one stays visibly short of the
notch rule.

### (c) Must stay windows

* **polkit** (`omarchy.polkit`): an authentication dialog must be its own window
  (SURFACE-HOSTING §6 rule 2).
* **lock** and **lock-explorer** and **face-lock**: lock-screen surfaces; a lock that
  lives inside a surface the session can run under is not a lock. Lock-explorer
  designs and previews lock screens.
* **arcdock's dock** (bottom layer windows), **background** (wallpaper, video),
  **notifications/osd originals** (replaced by the existing companions), and
  anything that needs the whole screen or video. A picker that is *fullscreen by
  design* (the speed-test dials) is in (a').

## What was verified, and how

`dev/overlays.sh` (141 checks):

* **A** drives `OverlayHosting.qml` against the REAL emoji picker, reminder flow,
  image picker and clipboard (the clipboard from a sandboxed copy: the real file
  reaps the live session's clipboard watchers when it loads and writes its history):
  load, find the window, arm, open, the window never maps, only the card moves, size
  is the card's own, colours kept, focus target found, live text in the card, give
  back, the picker is told it closed, the window is the size it had.
* **B** runs the whole route in a real throwaway notch: the companion's `Facade.qml`
  laid out like the plugins folder (so its bridge path is the live one), a summons,
  the notch grows to the card, the picker's window never maps, asking again keeps it,
  the back strip closes it (the picker's books balance), the picker's own Esc closes
  the notch's copy, `hide` closes it, and a picker opened over the menu returns to
  the menu on back.
* **C** uses a fixture picker (small window, same shape) for what the real ones can't
  safely do on a live session, which is *map*: setting off means its own window opens
  as ever; hosted then switched off means the window opens again (the binding was put
  back, not broken); the notch being away (quiet) means the picker opens as itself and
  is not lost.
* **D** the four manifests validate with `omarchy plugin validate`, the one go-between
  is byte-identical across them, ids and `clonedFrom` match, `install.sh` syncs them.

The notch closes an open panel when the compositor's focus moves (its focus grab);
on a shared session something else moving focus closes a hosted picker under a test.
The suite asks again up to three times before it counts a summons as failed, and
reads the picker's own books as `opens - closes` so a retry cannot change a count.

Not verified: a real pick (Enter) on any picker (it types, pastes, sets a theme or
schedules a reminder: never sent), the keyboard reaching the card on a mapped notch
window (the harness can say the target was found and asked for focus, not synthesise
keys), and installing the companions on the live session (the install restarts the
shell, and two other agents are installing branches).

## Merging

* `Bar.qml`: the `hosting` property now names `guestHosting`; `PanelHosting` is
  unchanged and still `panelHosting`. The overlay block (`overlayApi` and helpers) and
  the `Repeater` of four `Companion`s are new and self-contained; the other changes
  are the `layer.enabled` condition on `hostedSlot`, the `notchHostedOverlays` setting
  and two IPC functions (`overlays`, `overlayHostingSetting`). `Companion.qml` gains
  `facadeKey` (a bridge shared by several companions keeps one go-between each).
* With `plugins-in-notch`: its `stepBackFromHosted` and `notchHostedTopInset` apply to
  a picker unchanged (they work on `hostedOpen`/`hostedSlot`). Its `ensureContent()`
  is in `PanelHosting.take`, not here.
* With `back-one`: `overlayReleased()` calls `window.goBack()`, the strip's own path,
  so origin return comes from whatever `goBack` does there.
