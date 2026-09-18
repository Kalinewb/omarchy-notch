# Integrating with the notch

The notch can host another Omarchy plugin's UI. Declare an integration and your
panel opens **inside** the notch — on its black surface, in its text colours, at
its radius, on its motion — instead of in a window of your own. Short status
lines ("Switching to test…") can appear in the resting notch.

Your plugin keeps working exactly as it does today everywhere else: under
`omarchy.bar`, under another bar, with the notch removed, or with the user
switching your integration off. The notch tells you which of those you are in,
and you decide what to draw.

Contract version **1**. `graveklar.notch` accepts contracts 1 to 1.

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
  "entryPoints": { "barWidget": "Widget.qml", "notch": "NotchIntegration.qml" },
  "notch": { "contract": 1 }
}
```

- `notch.contract` — the contract version you wrote against. Required.
- `entryPoints.notch` — your integration file. Optional: without it you can
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
| `bad-contract` | `notch.contract` isn't a positive integer |
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
itself, with no change to your plugin at all.** It takes your panel's content
while the panel is open, grows to the size you asked your own card for, and
gives it back exactly as it found it when it closes. Your own window never maps,
so there is nothing for you to suppress.

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
  property var notchHost: null

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

## 3. `notchHost`

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

Your **bar widget** is handed the same host, plus `notchScreen` — the name of
the screen that copy of the widget is on. Declare both and the notch fills them
in; under any other bar neither is ever set, so there is no code path to guard.

```qml
Item {
  property var notchHost: null
  property string notchScreen: ""
  property bool ownPopupShown: false

  function press() {
    // Pass notchScreen, or a click on your second monitor opens the panel on
    // the first.
    var result = notchHost ? notchHost.openPanel("main", notchScreen) : "no-host"
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
| `notchHost`, `notchScreen` | once, when it is created |
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
- No colour that didn't come from `notchHost`. No theme colours, no gradients,
  no translucency, no blur.
- No radius that isn't `notchHost.radiusFor(...)`.
- Escape closes. If you have a list, typing should search it and Return should
  run the picked row.

```qml
import QtQuick

Item {
  property var notchHost: null
  property string notchScreen: ""
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
    color: notchHost ? notchHost.foreground : "#ffffff"
    font.family: notchHost ? notchHost.fontFamily : ""
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
notchHost.claim({
  title: "Switching to test…",     // required, cut at 60 characters
  detail: "profile",               // optional, cut at 80
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
| **present** | a notch is running and is the bar | `notchHost.present` | heartbeat fresh, or `omarchy-shell notch integration <id>` exits 0 |
| **accepted** | it accepted *your* integration | `notchHost.accepted` | heartbeat `accepted[<id>]`, or that verb's `accepted` |
| **shown** | this panel or claim is on screen now | the return of `openPanel` / `claim` | the stdout of the IPC call |

Two rules:

1. **Switch a *standing* UI off on `accepted`; switch a *per-event* UI off only
   on that event's own `opened` or `shown`.** Anything else means: do it
   yourself, now. A widget's popup is per-event. A button's "busy" styling is
   standing.

2. **A surface that exists to warn the user** — an authentication or sudo
   prompt, an identity check, a camera-in-use cue: anything an attacker on the
   same machine would want hidden — **may stand down only on an in-process
   `notchHost` answer**, from code the shell itself loaded. When your answer
   arrives from outside the shell (the heartbeat file, an `omarchy-shell` exit
   code, `NotchLink`), you may **mirror** into the notch but must keep your own
   UI regardless of the answer, `shown` included. Any process running as the
   user can write that file or stand in for that answer, so it cannot prove your
   warning is on screen.

### Outside the shell: `NotchLink.qml`

A service, a CLI or a panel that never gets a `notchHost` reads a small file the
notch keeps fresh at `$XDG_RUNTIME_DIR/graveklar.notch/platform.json`:

```json
{ "contract": 1, "features": ["panel", "activityViews", "heartbeat"],
  "generation": "1789650000123-4821", "beatAt": 1789650004123, "staleAfterMs": 6000,
  "present": true, "hidden": false, "screens": ["eDP-1"],
  "accepted": { "acme.demo": { "contract": 1 } },
  "declined": { "acme.future": "contract-newer" } }
```

Treat the notch as absent when the file is missing, `present` is false,
`beatAt` is older than `staleAfterMs`, or `contract` is below yours.

**Copy `platform/NotchLink.qml` from the notch's repository into your plugin.**
Don't import it from the notch's folder — your plugin would break whenever the
notch isn't installed.

```qml
NotchLink {
  id: notch
  pluginId: "acme.demo"
  shell: root.shell        // optional: skips everything when another bar is active
}

notch.claim({ title: "Switching to test…", priority: "persistent", ttlMs: 30000 },
            function (result) { if (result !== "shown") showMyOwnCue() })
```

`generation` changes when the notch is rebuilt (any plugin install or update
does that). `NotchLink` re-claims what you were holding; until the re-claim
answers, your callback has already been told `absent`, so draw your own.

## 7. When the notch goes away

| what happens | what you get |
|---|---|
| the user switches your integration off | `accepted` false at once; your panel closes and your claims are released |
| an unrelated notch setting changes | nothing: your integration is not reloaded, your panel stays open |
| a plugin is installed or updated (every plugin reloads) | your integration is destroyed and loaded again; the heartbeat says `present: false` as it goes, then a new `generation` |
| another bar is made active, or the notch is removed | no `notchHost`; the heartbeat goes stale within 6 s and the IPC target is gone |
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
  `"name" in notchHost` or `features.indexOf("name") !== -1`.
- A rename, a removed member, a changed result word or a changed queue rule
  bumps `contract`. The notch keeps accepting the older version for at least one
  release.
- A plugin written for a newer contract than the notch implements gets
  `contract-newer` and stays standalone. One written for an older one than the
  notch still accepts gets `contract-older`.

| contract | notch release | changes |
|---|---|---|
| 1 | 0.1.0 | panels, activity claims, the heartbeat |
