# Surface hosting

A **host** can draw another Omarchy plugin's UI on its own surface. Declare an
integration and your panel opens **inside** the host — on its surface, in its
text colours, at its radius, on its motion — instead of in a window of your
own. Short status lines ("Switching to test…") can appear in the host's resting
view.

Nothing here is specific to one host. The contract is named for what it does,
not for who implements it: a plugin that implements it works with any host that
does, and nothing in this document requires reading a host's source. Today
`kalinewb.notch` is the only host, and it is the one this document uses for
examples — where it says "the notch", read "the host you are running under".

Your plugin keeps working exactly as it does today everywhere else: under
`omarchy.bar`, under another bar, with the host removed, or with the user
switching your integration off. The host tells you which of those you are in,
and you decide what to draw.

Contract version **1**. `kalinewb.notch` accepts contracts 1 to 1.

---

## 0. Which of these are you?

Three different things get called "integrating with the notch", and only one of
them is this contract. Find your row first.

| you have | what happens | where to read |
|---|---|---|
| an ordinary bar widget with a pop-out panel (a `KeyboardPanel`) | the host draws that panel inside itself, **with no change to your plugin** | §1's *You may not need any of this*, then §11 for what your own code sees while it is hosted |
| UI that is not a pop-out panel, or you want activities, `available`, or a layout meant for the notch | you declare an integration and write a panel for it | all of this document |
| a plugin that wants to reach another plugin inside the shell | there is no general answer, and the notch's menu bridge is not one — §12 | §12 |
| a plugin you want the notch to be able to **install** | the catalogue, which is not open to everyone — §13 | §13 |

---

## 1. Declare it

Add two things to your `manifest.json`:

```json
{
  "schemaVersion": 1,
  "id": "acme.demo",
  "name": "Acme Demo",
  "version": "1.0.0",
  "description": "…",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "Widget.qml", "surface": "SurfaceIntegration.qml" },
  "surface": { "contract": 1 }
}
```

- `surface.contract` — the contract version you wrote against. Required.
- `entryPoints.surface` — your integration file. Optional: without it you can
  still claim activities, which suits a service or a CLI that only reports
  status.

`omarchy plugin validate` accepts both: it only requires that every entry point
is a relative path with no `..` that exists, and it refuses any symlink inside a
plugin folder.

> **Never commit a symlink anywhere in your plugin repository, test fixtures
> included.** `omarchy plugin update` re-validates after fast-forwarding and
> rolls the update back if validation fails, so one committed symlink silently
> stops every future update of your plugin. Create them in a temp folder at test
> time instead.

The notch checks the same things itself, because a plugin folder can be copied
in without ever being validated. It will decline your integration if:

| problem | meaning |
|---|---|
| `schema` | `schemaVersion` isn't 1 |
| `bad-id` | the id isn't a plain id, or is in Omarchy's namespace |
| `self` | the manifest claims to be the notch |
| `bad-contract` | `surface.contract` isn't a positive integer |
| `entry-unsafe` | the entry path is absolute, climbs out, or is a symlink |
| `entry-missing`, `entry-not-qml` | the entry isn't there, or isn't `.qml` |
| `own-window` | the entry file mentions `PanelWindow`, `PopupWindow` or `FloatingWindow` |
| `duplicate-id` | another folder already claimed this id |

The `own-window` check reads only the entry file, so it catches the obvious case
and no more. **The rule is binding anyway:** an integration draws inside the
notch and never opens a window.

### You may not need any of this

If your plugin is an ordinary Omarchy bar widget with a pop-out panel — a
`KeyboardPanel` holding your content — **the notch can already draw it inside
itself, with no change to your plugin at all.** It opens your panel, takes its
content, grows to the size you asked your own card for, and gives it back exactly
as it found it when it closes. Your own window never maps, so there is nothing
for you to suppress.

What that means for the code you have already written:

| your code | while the notch is drawing it |
|---|---|
| `opened` / your `PanelController` | **true** — so `onOpenedChanged`, and anything on `running: opened`, runs exactly as it does in your own window |
| `KeyboardPanel.open`, and the window it maps | false, and never mapped. The notch holds your window down at that one binding and puts it back afterwards |
| `KeyboardPanel.focusTarget` | given the keyboard on the notch's surface, because your own window is not there to focus |
| your `close()` (Escape, a timeout, your IPC) | closes the notch's copy too |
| the notch closing the panel | your panel is told it closed first, so what you run while open stops before anything is given back |

So a panel that does its work when it opens keeps working: Omarchy's Wifi panel
starts its only scan in `onOpenedChanged`, and that is what fills the network
list in the notch.

That covers most widgets. Declare an integration when you want more than your
panel in the notch:

- a panel that is **not** a pop-out (your UI lives somewhere else entirely)
- **activities** — a line in the resting notch while something is happening
- control over *when* the notch may show you, through `available`
- your own layout for the notch specifically, rather than the panel you already
  draw

Both can be true at once: a plugin with a hostable panel and a declared
integration gets the integration's panel, because you asked for it explicitly.

## 2. The integration file

```qml
import QtQuick

Item {
  // The notch sets this. Until it does, there is no notch.
  property var surfaceHost: null

  // Optional: say false to decline for now. The notch shows the reason and you
  // keep your own UI.
  property bool available: true

  // Optional: the panel the notch draws for you.
  property Component panel: Component { DemoPanel {} }

  // Optional: named rows for activities you claim.
  property var activityViews: ({ "progress": progressRow })
  property Component progressRow: Component { ProgressRow {} }
}
```

Rules:

- **It exists once**, however many monitors there are — so anything with a cost
  (a `FileView`, a `Process`) belongs here, not in the panel. Your panel is
  created once per screen from the one Component.
- **Imports:** QtQuick, Quickshell, Quickshell.Io, `qs.Commons`, `qs.Ui`, and
  relative imports of your own files. `qs.services` is not available to files
  outside the shell root.
- **No `IpcHandler`.** Your widget or service already owns your IPC target; a
  second registration conflicts.
- **No windows.**
- **No writes under `~/.config/omarchy/plugins`** — every write there reloads
  every plugin.
- Set `available` honestly. It is how you decline without looking broken.

The file is loaded when your plugin is accepted and unloaded when the user
switches it off. Unrelated settings changes never reload it.

## 3. `surfaceHost`

The only notch object you ever get. It is scoped to your plugin: everything you
do through it is attributed to your id, and it reaches nothing else.

| member | type | what |
|---|---|---|
| `contract` | int | the notch's contract version |
| `features` | list | `["panel", "activityViews", "heartbeat"]`; feature-detect against it |
| `pluginId` | string | your id |
| `present` | bool | this notch is alive and is the bar |
| `accepted` | bool | it accepted *your* integration |
| `reason`, `reasonDetail` | string | why not, when `accepted` is false |
| `hidden` | bool | the bar is hidden (`omarchy toggle bar`) |
| `color`, `foreground`, `secondary`, `accent` | color | the notch's colours |
| `radius` | real | the notch's radius |
| `radiusFor(size)` | real | that radius, never more than half of `size` |
| `fontFamily` | string | the bar's font |
| `restHeight` | real | the resting notch's height |
| `maxPanelWidth`, `maxPanelHeight` | real | what a panel may use |
| `growHeightMs`, `growWidthMs`, `growWidthDelayMs`, `shrinkMs`, `fadeInMs`, `fadeOutMs`, `springDamping` | number | the notch's motion, if you must match it |
| `panelOpen`, `panelRoute`, `panelScreen` | bool/string | your panel's state |
| `openPanel(route, screenName)` | string | `opened`, `closed` or `declined:<reason>` |
| `closePanel()` | string | `closed` or `unknown` |
| `claim(activity)` | string | `shown`, `queued` or `declined:<reason>` |
| `release(key)` | string | `released` or `unknown` |

Your **bar widget** is handed the same host, plus `surfaceScreen` — the name of
the screen that copy of the widget is on. Declare both and the notch fills them
in; under any other bar neither is ever set, so there is no code path to guard.

```qml
Item {
  property var surfaceHost: null
  property string surfaceScreen: ""
  property bool ownPopupShown: false

  function press() {
    // Pass surfaceScreen, or a click on your second monitor opens the panel on
    // the first.
    var result = surfaceHost ? surfaceHost.openPanel("main", surfaceScreen) : "no-host"
    // Per-event: skip your own popup only for the event the notch took.
    if (result !== "opened") ownPopupShown = true
  }
}
```

## 4. Panels

Your panel Component is created inside the notch's own panel surface. The notch
sets, where you declare them:

| property | how |
|---|---|
| `surfaceHost`, `surfaceScreen` | once, when it is created |
| `route` | **bound** — a later `openPanel` at another route changes it on the same item |
| `maxWidth`, `maxHeight` | bound to what the notch can give you |
| `closeRequested()` | connected: emit it to close |

It also calls `open(route)` on every open and `close()` when it closes, if you
declare them.

Size yourself with `implicitWidth` and `implicitHeight`; the notch grows to
them on its own spring. Do not animate your own container — the notch is already
moving.

**What a panel may not do** (DESIGN-PHILOSOPHY.md):

- No background of its own. The notch's black surface is the background.
- No colour that didn't come from `surfaceHost`. No theme colours, no gradients,
  no translucency, no blur.
- No radius that isn't `surfaceHost.radiusFor(...)`.
- Escape closes. If you have a list, typing should search it and Return should
  run the picked row.

```qml
import QtQuick

Item {
  property var surfaceHost: null
  property string surfaceScreen: ""
  property string route: "main"
  property real maxWidth: 400
  property real maxHeight: 400
  signal closeRequested()

  implicitWidth: 320
  implicitHeight: 180

  focus: true
  Keys.onEscapePressed: closeRequested()

  Text {
    anchors.centerIn: parent
    text: "Acme · " + route
    color: surfaceHost ? surfaceHost.foreground : "#ffffff"
    font.family: surfaceHost ? surfaceHost.fontFamily : ""
  }
}
```

## 5. Activities

An activity is a short or ongoing line in the **resting** notch.

> Activities are accepted and queued today, but nothing draws them yet: a claim
> the queue would show answers `queued` rather than `shown`, and `activities()`
> reports `rendered: false`. Don't hide your own cue for one until this note is
> gone.

```qml
surfaceHost.claim({
  title: "Switching to test…",     // required, cut at 60 characters
  detail: "profile",               // optional, cut at 240
  key: "acme.demo.switch",         // your id, or your id + "." + anything
  priority: "persistent",          // transient | persistent | persistent-low
  ttlMs: 30000,
  glyph: "󰒓",
  progress: 0.4,                   // 0–1, or leave it out
  view: "progress",                // a name from activityViews
  panelRoute: "main",              // clicking it opens your panel there
  screens: []                      // empty means every screen
})
```

The queue, in plain words:

1. At most **two** are shown at a time.
2. A third **queues**, ordered by priority and then first-come.
3. A **transient** jumps the queue: it takes a slot from a slower activity,
   which goes back to the front of its own kind rather than being dropped.
4. Claiming the **same key** again replaces that activity in place — five volume
   presses are one line, not five.
5. A transient's life runs from when it is shown; one that waited more than ten
   seconds is dropped rather than shown late.
6. **Four at a time per plugin.** Beyond that you get `declined:owner-limit`.
7. Releasing a key, or the notch no longer accepting you, takes yours away.

Anyone looking at the screen sees an activity, so **never put a secret, a token
or an identity in one**.

## 6. Switching your own UI off

Three levels, and you use the one your code can reach:

| level | means | in the shell | outside it |
|---|---|---|---|
| **present** | a notch is running and is the bar | `surfaceHost.present` | heartbeat fresh, or `omarchy-shell notch integration <id>` exits 0 |
| **accepted** | it accepted *your* integration | `surfaceHost.accepted` | heartbeat `accepted[<id>]`, or that verb's `accepted` |
| **shown** | this panel or claim is on screen now | the return of `openPanel` / `claim` | the stdout of the IPC call |

Two rules:

1. **Switch a *standing* UI off on `accepted`; switch a *per-event* UI off only
   on that event's own `opened` or `shown`.** Anything else means: do it
   yourself, now. A widget's popup is per-event. A button's "busy" styling is
   standing.

2. **A surface that exists to warn the user** — an authentication or sudo
   prompt, an identity check, a camera-in-use cue: anything an attacker on the
   same machine would want hidden — **may stand down only on an in-process
   `surfaceHost` answer**, from code the shell itself loaded. When your answer
   arrives from outside the shell (the heartbeat file, an `omarchy-shell` exit
   code, `SurfaceLink`), you may **mirror** into the notch but must keep your own
   UI regardless of the answer, `shown` included. Any process running as the
   user can write that file or stand in for that answer, so it cannot prove your
   warning is on screen.

### Outside the shell: `SurfaceLink.qml`

A service, a CLI or a panel that never gets a `surfaceHost` reads a small file the
notch keeps fresh at `$XDG_RUNTIME_DIR/kalinewb.notch/platform.json`:

```json
{ "contract": 1, "features": ["panel", "activityViews", "heartbeat"],
  "generation": "1789650000123-4821", "beatAt": 1789650004123, "staleAfterMs": 6000,
  "present": true, "hidden": false, "screens": ["eDP-1"],
  "accepted": { "acme.demo": { "contract": 1 } },
  "declined": { "acme.future": "contract-newer" } }
```

Treat the notch as absent when the file is missing, `present` is false,
`beatAt` is older than `staleAfterMs`, or `contract` is below yours.

**Copy `platform/SurfaceLink.qml` from the notch's repository into your plugin.**
Don't import it from the notch's folder — your plugin would break whenever the
notch isn't installed.

```qml
SurfaceLink {
  id: notch
  pluginId: "acme.demo"
  shell: root.shell        // optional: skips everything when another bar is active
}

notch.claim({ title: "Switching to test…", priority: "persistent", ttlMs: 30000 },
            function (result) { if (result !== "shown") showMyOwnCue() })
```

`generation` changes when the notch is rebuilt (any plugin install or update
does that). `SurfaceLink` re-claims what you were holding; until the re-claim
answers, your callback has already been told `absent`, so draw your own.

## 7. When the host goes away

| what happens | what you get |
|---|---|
| the user switches your integration off | `accepted` false at once; your panel closes and your claims are released |
| an unrelated notch setting changes | nothing: your integration is not reloaded, your panel stays open |
| a plugin is installed or updated (every plugin reloads) | your integration is destroyed and loaded again; the heartbeat says `present: false` as it goes, then a new `generation` |
| another bar is made active, or the notch is removed | no `surfaceHost`; the heartbeat goes stale within 6 s and the IPC target is gone |
| the notch fails to load | same |
| the bar is hidden (`omarchy toggle bar`) | `accepted` stays true, but `openPanel` and `claim` answer `declined:hidden` |

## 8. Security

- Your integration QML runs inside the shell with your plugin's privileges — the
  same as your widget already does.
- IPC claims, their answers and the heartbeat file **can all be forged** by any
  process running as the user. See rule 2 above.
- Never pass a secret through a claim.

## 9. Testing yours

```sh
omarchy-shell notch integrations          # every candidate, and why each was accepted or not
omarchy-shell notch integration acme.demo # just yours
omarchy-shell notch panel acme.demo main  # open your panel
omarchy-shell notch activities            # what is in the queue
omarchy-shell notch rescanIntegrations    # look again now
```

In a throwaway Quickshell instance, the notch only looks at the folder you point
it at, and only when asked:

```sh
NOTCH_FORCE_PLATFORM=1 NOTCH_PLUGINS_DIR=/tmp/fixtures/plugins \
NOTCH_PLATFORM_ENABLED='*' NOTCH_PLATFORM_STATE_DIR=/tmp/state \
quickshell -p /tmp/root -n
```

The root needs `Commons` and `Ui` symlinked from `$OMARCHY_PATH/shell`, and a
file inside it that imports each `qs.*` module your integration uses — otherwise
Quickshell won't resolve those imports from a file outside the root.

`dev/fixtures/platform/plugins/acme.demo` in the notch's repository is a
complete working example, and it is what `dev/platform.sh` tests.

**Test standalone too:** run under `omarchy.bar` and check that every path still
works with no notch at all.

## 10. Versioning

- Additive changes — a new host member, a new claim field, a new verb — do not
  bump the contract. They appear in `features`, and you feature-detect with
  `"name" in surfaceHost` or `features.indexOf("name") !== -1`.
- A rename, a removed member, a changed result word or a changed queue rule
  bumps `contract`. The notch keeps accepting the older version for at least one
  release.
- A plugin written for a newer contract than the notch implements gets
  `contract-newer` and stays standalone. One written for an older one than the
  notch still accepts gets `contract-older`.

| contract | notch release | changes |
|---|---|---|
| 1 | 0.1.0 | panels, activity claims, the heartbeat |

---

## 11. The unmodified path, in full

This is the path almost every plugin is on, including the two the notch knows
best (Face ID and Profiles) and every Omarchy panel it draws. It has no manifest
key and nothing to opt into: the host recognises the shape, takes the panel, and
gives it back. Written down here because it is a contract whether or not anyone
wrote it down, and because the alternative is reading the host's source.

### What is recognised

Your widget's root must have, in its own `data` or one `Loader` deep and no
deeper:

- a **`KeyboardPanel`** with something in its `contentItem`, and
- a **`PanelController`** — the object holding the open state.

One level of Loader, and no further: a panel behind two of them is as likely to
belong to something else as to you. Both shapes in the wild work — a widget that
*is* its `Panel` (Omarchy's audio), and a `BarWidget` that loads `Panel.qml`
through a `Loader` (its clock, weather).

Declined, in these words, if not: `no widget`, `no panel`, `panel has nothing in
it`, `no panel controller`. The user sees the reason in Settings → Integrations.

### What the host does, in order

1. Takes **every** item in your panel's `contentItem` — not just the first; a
   panel with dialogs anchored over its column travels whole — recording each
   one's parent and size first.
2. Parents them into its own slot. An item that filled its parent is re-filled
   to the slot; one that did not is given the size it had, because it was being
   sized by the card it just left.
3. Breaks the binding that maps your window (`open: root.opened` on every panel
   built on Omarchy's `Ui/Panel`) and sets it false, **then** opens your
   controller. In that order, or your window maps for the frame between the two.
4. On close: tells your controller it closed — while the binding is still broken,
   so you pack up with nothing on screen — then puts the items back where they
   were, at the size they were, and restores the binding.

### What you can rely on

Everything in §1's table: `opened` is true, your `focusTarget` has the keyboard,
your `close()` closes the host's copy, and you are told it closed before anything
is handed back. Your bindings, your model and your layout survive the move —
that is proven rather than assumed (`dev/harness/reparent-probe.qml` moves
Omarchy's real audio panel into a foreign window and back, and `dev/hosting.sh`
keeps it proven against the real widget, a fixture that counts what it is told,
and a widget whose panel is behind a Loader).

### What you must not assume

- **Your window is not there.** Anything keyed to it — its screen, its geometry,
  its `visible`, an animation you run on it — is not running.
- **Your colours are not yours.** `bar.foreground`, `background` and `urgent`
  are the host's for as long as it holds you, and anything you read from
  Omarchy's `Color`/`Style` singletons instead is drawn through the host's own
  transform (see DESIGN-PHILOSOPHY.md: hue out, lightness back). Neutral greys
  are untouched; a saturated accent is not.
- **Nothing moves where it cannot be seen.** A looping animation inside a panel
  that is drawn at zero opacity still repaints the host's surface every frame.
  Gate yours on being visible. `dev/perf.sh` is the measurement.
- **You may be given back at any moment** — the user switching you off, the host
  going away, another panel opening. Handle `close()` as a real close.

### Turning it off

The user owns it: Settings → Integrations, per widget, off by default. Switching
it off gives you your own window back at once, with no reload. Nothing about
your plugin is modified, ever — no file is touched and no property of yours is
rewritten except the one binding above, which is put back.

## 12. The menu bridge is not an extension point

The notch has a bridge (`bridge/NotchMenuBridge.qml`, a singleton both sides
resolve through the same `qmldir`) that lets one specific companion plugin —
`kalinewb.notch-menu`, which Omarchy routes every `omarchy.menu` call to —
reach the notch inside one shell process. Omarchy gives plugins no way to reach
each other, so this looks like the general answer to that, and it is not:

- **It is deliberately narrow.** `target` is not the notch's root. It is
  `MenuCompanion.qml`'s `menuApi`, which can open the menu, close it, refresh it
  and answer whether it is open. Anything that can load the connector could
  otherwise reach the notch's shell facade and its settings.
- **It is versioned and refused on mismatch.** `apiVersion` is bumped when
  `menuApi`'s shape changes; the companion refuses a mismatch and uses Omarchy's
  own menu instead. Singleton code is cached for the life of the shell process,
  so a change needs a shell restart — `install.sh` does one.
- **It is private.** Not because the mechanism is secret (it is thirty lines and
  in this repository), but because a second consumer would make `menuApi` a
  public surface that has to keep its shape, and there is no version of that we
  have thought through.

If you need to reach another plugin, the supported routes are the ones Omarchy
already has: your own IPC target (`omarchy-shell <your-id> …`), a file both
sides watch, or — for the host specifically — `surfaceHost` (§3) and
`SurfaceLink.qml` (§6) from outside the shell.

## 13. The catalogue: what the notch can install

Setup → Plugins installs from `plugins/catalogue.json` and nothing else. An id
that is not in it cannot be installed from the notch, and two are refused by
name. That is a deliberately short list, not an oversight, and the rules matter
more than the membership:

- **Pinned URL.** Every entry names the exact GitHub URL it may be installed
  from. A repository that has moved is a new entry, reviewed again.
- **Checked three times.** The card asks GitHub for the exact commit and that
  commit's manifest id and kinds before it offers to install; the job checks the
  commit, id and kinds again before anything lands in the plugins folder; and
  upstream clones once more afterwards, so the result is verified too. A folder
  that fails the last check is moved aside to `plugins/.notch-refused.<name>.<ms>`,
  which Omarchy ignores, and the notice names it for deleting.
- **A bar is refused.** A plugin whose kinds have become `bar` would replace the
  notch itself.
- **Nothing here asks for your password.** Setup and removal happen in each
  plugin's own panel. A plugin whose install needs root does not fit the page as
  it stands — that is an open question, not a gap to route around.
- **No IPC call installs anything.** `notch plugins open|close|status|refresh`
  is the whole surface; there is no verb that installs, updates, enables, sets
  up or removes.

If you want a plugin listed, the honest answer today is that the list is
maintained by hand, in this repository, by people who have read the plugin. What
a general answer would need is written up in INTEGRATION-SCOPE.md §3.
