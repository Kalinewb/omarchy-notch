import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "notifications.js" as Notifications

// Omarchy's toasts, shown in the notch.
//
// The notch does not own org.freedesktop.Notifications, never watches the bus,
// never calls CloseNotification and never touches do-not-disturb. Omarchy keeps
// the cards on its screen in one file, ~/.local/state/omarchy/notifications/
// live.json, rewritten whole a moment after a card arrives, changes or leaves,
// so watching that file is how a toast is found: a row appearing claims an
// activity, a row changing claims it again, a row leaving lets it run out its
// own time. Omarchy's own toast still draws as well, unless "Suppress Omarchy's
// own toast" is on: then the notifications companion (Companion.qml) keeps it
// off screen while this shows it.
//
// The notch's copy keeps its own time: it stays until the user acts on it, or
// closes a number of seconds after it appears (the two settings), whatever
// Omarchy's own toast does meanwhile. Acting is Omarchy's own: a left click
// runs the toast's default action through Omarchy's notification service and a
// right click dismisses it there (`interact`).
Item {
  id: source
  visible: false

  property var bar: null

  // A test notch never reads the user's folder: the gate follows updatesEnabled.
  readonly property bool forced: Quickshell.env("NOTCH_FORCE_NOTIFICATIONS") === "1"
  readonly property string dir: {
    var override = Quickshell.env("NOTCH_NOTIFICATIONS_DIR")
    if (override) return override
    if (!bar || bar.harnessed) return ""
    return (Quickshell.env("HOME") || "") + "/.local/state/omarchy/notifications"
  }
  readonly property string livePath: dir === "" ? "" : dir + "/live.json"
  readonly property bool enabled: !!bar && bar.notchNotifications && dir !== ""
    && ((!!bar.shell && !bar.harnessed) || forced)

  // When this source came up. A row stamped before it is never drawn: Omarchy
  // restores the cards it had on screen when it restarts, and anything older
  // is something the user has already seen.
  property real startedAt: 0

  // key -> { stamp, state, key, drawn, dismissed, live, data, deadline }
  // The key is the row's own, in Omarchy's file; the stamp is the row's `ts`
  // (seconds), which changes when Omarchy updates the card in place.
  // state: shown | queued | declined:<r> | waiting | dismissed | closed
  //        | dropped | ignored-old | stock
  // stock: left to Omarchy's own toast (a card with a code in it).
  // live: the row is still in Omarchy's file (its toast has not ended).
  // drawn: it has been on the notch, so it may wait for a free line and still
  //        be worth showing; a card that only ever waited is let go with its row.
  // data: what the file said, kept so the copy outlives the row.
  // deadline: when the timed copy closes (0 until it is on screen).
  property var entries: ({})
  // inotify | poll | waiting-file
  property string watchMode: "waiting-file"
  // Reads in a row that would not parse, and whether that has been said.
  property int readFailures: 0
  property bool warned: false
  // The two settings: stay until acted on, or close after a number of seconds.
  readonly property bool stay: !!bar && bar.notchNotificationStay
  readonly property int lifetimeMs: Notifications.lifetimeMs(stay, bar ? bar.notchNotificationSeconds : Notifications.SECONDS_DEFAULT)
  // The pointer is over the notch while one is showing: its clock waits.
  readonly property bool pointerOver: {
    var windows = bar ? bar.notchWindows : []
    for (var i = 0; i < windows.length; i++) if (windows[i].pointerOnNotch) return true
    return false
  }
  // Watching the file is what makes a read prompt; reading it on a timer is what
  // makes it certain. `poll` asks for the timer alone (a test, or a machine
  // where the watch will not hold).
  readonly property bool pollOnly: Quickshell.env("NOTCH_NOTIFICATIONS_WATCH") === "poll"

  function keyFor(name) { return "notch.notifications." + name }

  function copyEntries() {
    var out = ({})
    for (var k in entries) out[k] = entries[k]
    return out
  }

  function setEntry(name, patch) {
    var next = copyEntries()
    var was = next[name] || {}
    var merged = ({})
    for (var k in was) merged[k] = was[k]
    for (var j in patch) merged[j] = patch[j]
    next[name] = merged
    entries = next
  }

  function dropEntry(name) {
    if (entries[name] === undefined) return
    var next = copyEntries()
    delete next[name]
    entries = next
  }

  // How many are on the queue's books right now. A burst of toasts must not
  // fill the activity queue ahead of an integration's own lines, so the source
  // holds the rest back itself rather than leaning on the queue's owner limit.
  function claimedCount() {
    var n = 0
    for (var name in entries) {
      var state = entries[name].state
      if (state === "shown" || state === "queued") n++
    }
    return n
  }

  function claim(name, entry) {
    if (!bar || !bar.platform) return
    if (stay) makeRoom(name)
    var result = bar.platform.claimInternal("notch.notifications", Notifications.claimFor(name, entry))
    // A claim again (the toast was updated in place) starts the clock again.
    setEntry(name, { stamp: Number(entry.ts), state: result, key: keyFor(name), data: entry, drawn: result === "shown" || result === "queued", deadline: 0 })
  }

  // The queue holds two lines and a third would wait ten seconds and be
  // dropped, which for a copy that stays until it is acted on is a notification
  // silently lost. So the newest takes the screen and the oldest one on it steps
  // back to waiting, and comes back (newest first) when a line frees up.
  function makeRoom(name) {
    var shownNames = []
    for (var n in entries) if (n !== name && entries[n].state === "shown") shownNames.push(n)
    if (shownNames.length < 2) return
    shownNames.sort(function(a, b) { return entries[a].stamp - entries[b].stamp })
    var oldest = shownNames[0]
    release(oldest)
    setEntry(oldest, { state: "waiting", deadline: 0 })
  }

  function release(name) {
    if (bar && bar.platform) bar.platform.releaseInternal("notch.notifications", keyFor(name))
  }

  // The newest thing waiting gets the slot the departing one freed.
  function promoteWaiting() {
    var best = "", bestStamp = -1
    for (var name in entries) {
      var e = entries[name]
      if (e.state !== "waiting" || e.dismissed || !e.data) continue
      if (e.stamp > bestStamp) { bestStamp = e.stamp; best = name }
    }
    if (best !== "") claim(best, entries[best].data)
  }

  // A row, new or changed. A row Omarchy has not touched since the last read is
  // nothing to do; one it has updated in place (a newer `ts`) is claimed again,
  // even if the user had dismissed the copy: it says something new.
  function changed(row) {
    var name = row.key
    var existing = entries[name]
    if (existing && Number(row.ts) <= existing.stamp + 0.0005) return
    var base = { stamp: Number(row.ts), key: keyFor(name), data: row, live: true, dismissed: false, deadline: 0 }
    if (row.ts * 1000 < startedAt) {
      if (existing && (existing.state === "shown" || existing.state === "queued")) release(name)
      setEntry(name, merged(base, { state: "ignored-old" }))
      return
    }
    // A card with a code in it is kept in the file only as a placeholder, and
    // its buttons are Omarchy's: its toast stays.
    if (row.redacted) {
      if (existing && (existing.state === "shown" || existing.state === "queued")) release(name)
      setEntry(name, merged(base, { state: "stock" }))
      promoteWaiting()
      return
    }
    var onQueue = !!existing && (existing.state === "shown" || existing.state === "queued")
    if (!onQueue && claimedCount() >= Notifications.OWNER_LIMIT) {
      setEntry(name, merged(base, { state: "waiting", drawn: !!existing && existing.drawn === true }))
      return
    }
    claim(name, row)
    setEntry(name, { live: true, dismissed: false })
  }

  function merged(a, b) {
    var out = ({})
    for (var k in a) out[k] = a[k]
    for (var j in b) out[j] = b[j]
    return out
  }

  // The row left Omarchy's file: its toast ended, there or here. A copy the
  // notch is showing (or has waiting, having shown it) runs on its own clock and
  // stays as it is -- only its link to Omarchy's toast is gone. Anything else
  // lets go, and so does everything when `force` says the file itself went.
  function gone(name, force) {
    var e = entries[name]
    if (e === undefined) return
    var keeps = force !== true && (e.state === "shown" || e.state === "queued" || (e.state === "waiting" && e.drawn === true))
    if (keeps) {
      if (e.live !== false) setEntry(name, { live: false })
      return
    }
    release(name)
    dropEntry(name)
    promoteWaiting()
  }

  // Take the notch's copy down and remember it was taken down, so it does not
  // come back while its file is still in the folder. `how` is the state it is
  // left in: dismissed (the user acted) or closed (its time ran out).
  function finish(name, how) {
    var e = entries[name]
    if (e === undefined) return
    release(name)
    if (e.live === false) dropEntry(name)
    else setEntry(name, { dismissed: true, state: how, deadline: 0 })
    promoteWaiting()
  }

  // Nothing is written and nothing is sent to Omarchy: dismissing clears the
  // notch's copy only. `interact` is what also tells Omarchy.
  function dismiss(key) {
    var name = nameFor(key)
    if (name === "") return false
    finish(name, "dismissed")
    return true
  }

  function nameFor(key) {
    for (var name in entries) if (keyFor(name) === key) return name
    return ""
  }

  // --- the user acts on a copy -----------------------------------------------
  //
  // Left click opens, right click dismisses, the way Omarchy's own toast does,
  // and by Omarchy's own calls rather than a copy of what they do:
  //
  //   - through the notifications companion, when it is loaded, straight into
  //     Omarchy's real service: its `activate` / `closeToast` for the row's key
  //     (the key in live.json is the key of the card on its screen);
  //   - otherwise through Omarchy's `notifications` IPC target, the one its own
  //     keybinds use, which acts on the newest popup (`invokeLast`, `dismissOne`)
  //     or, for a dismissal, one named by its summary;
  //   - a copy whose toast has already ended is no longer in Omarchy's service at
  //     all. Opening it then does what the service would have done with the
  //     toast's own data: run its argv the way Omarchy does, or focus its app
  //     with Omarchy's helper.
  //
  // Answers which way it went: service | ipc | local | notch | no-such-notification.
  //
  // The service is only used when it has all three calls; any other Omarchy
  // goes the IPC way, which is slower to name the card but never wrong.
  readonly property var service: {
    var facade = bar && bar.notificationsCompanion ? bar.notificationsCompanion.facade : null
    var stock = facade ? facade.stockItem : null
    return stock && typeof stock.activate === "function" && typeof stock.closeToast === "function"
      && typeof stock.rowIndexFor === "function" ? stock : null
  }

  // Whether Omarchy's service still has a card for this key on its screen.
  function inService(name) {
    var svc = service
    return !!svc && Number(svc.rowIndexFor(name)) >= 0
  }

  function newestLive() {
    var best = "", bestStamp = -1
    for (var name in entries) {
      var e = entries[name]
      if (e.live === false || e.state === "ignored-old") continue
      if (e.stamp > bestStamp) { bestStamp = e.stamp; best = name }
    }
    return best
  }

  function omarchyShell(args) {
    Quickshell.execDetached(["omarchy-shell", "-q"].concat(args))
  }

  function openLocally(data) {
    var argv = Notifications.argvFrom(data.execArgv)
    if (argv) { Util.execArgv(argv); return }
    if (data.app) Quickshell.execDetached([(bar ? bar.omarchyPath : "") + "/bin/omarchy-hyprland-focus-app", String(data.app)])
  }

  function interact(key, how) {
    var name = nameFor(key)
    if (name === "") return "no-such-notification"
    var e = entries[name]
    var data = e.data || {}
    var open = how === "open"
    var via = "notch"
    if (e.live !== false && inService(name)) {
      if (open) service.activate(name, true)
      else service.closeToast(name, "dismissed", true)
      via = "service"
    } else if (e.live !== false) {
      var newest = newestLive() === name
      if (open && newest) omarchyShell(["notifications", "invokeLast"])
      else if (open) { openLocally(data); omarchyShell(["notifications", "dismiss", String(data.summary || "")]) }
      else omarchyShell(newest ? ["notifications", "dismissOne"] : ["notifications", "dismiss", String(data.summary || "")])
      via = open && !newest ? "local" : "ipc"
    } else if (open) {
      openLocally(data)
      via = "local"
    }
    finish(name, "dismissed")
    return via
  }

  // --- the clock ---------------------------------------------------------------
  //
  // A line starts its time when it is actually on screen (the queue may hold it
  // back), waits while the pointer is over the notch, and closes when the time is
  // up. One that the queue dropped while it waited (it holds a transient ten
  // seconds) is marked so rather than left claiming a place.
  property real lastTick: 0
  function tick() {
    var now = Date.now()
    var dt = lastTick > 0 ? now - lastTick : 0
    lastTick = now
    if (!bar || !bar.platform) return
    var activity = bar.platform.activityState
    var onScreen = ({}), waiting = ({})
    for (var i = 0; i < activity.visible.length; i++) onScreen[activity.visible[i].key] = true
    for (var j = 0; j < activity.queued.length; j++) waiting[activity.queued[j].key] = true
    var shownKey = bar.activityLine ? String(bar.activityLine.key) : ""
    for (var name in entries) {
      var e = entries[name]
      if (e.state !== "shown" && e.state !== "queued") continue
      var key = keyFor(name)
      if (!onScreen[key] && !waiting[key]) { finish(name, "dropped"); continue }
      if (!onScreen[key]) { if (e.deadline) setEntry(name, { deadline: 0 }); continue }
      if (lifetimeMs <= 0) continue
      if (!e.deadline) { setEntry(name, { deadline: now + lifetimeMs }); continue }
      // The pointer is on it, or the notch is quiet and nobody can see it: the clock waits.
      if ((pointerOver && key === shownKey) || bar.quiet) { setEntry(name, { deadline: e.deadline + dt }); continue }
      if (now >= e.deadline) finish(name, "closed")
    }
  }

  Timer {
    id: clock
    interval: 200
    repeat: true
    running: source.enabled && source.claimedCount() > 0
    onRunningChanged: if (!running) source.lastTick = 0
    onTriggered: source.tick()
  }

  // --- the file ----------------------------------------------------------------
  //
  // live.json is read whole each time: it is a short list that Omarchy replaces
  // in one step. FileView's watch makes a read prompt; the timer makes it
  // certain, because a watch can go quiet (a file replaced under it, a dropped
  // inotify instance) and one missed read must never leave a line up for good.
  // A file that is not there is not an empty list: it means Omarchy's
  // notification service is off or has not started, so nothing is live and the
  // notch lets go rather than hold stale lines.
  FileView {
    id: liveFile
    path: source.enabled ? source.livePath : ""
    watchChanges: !source.pollOnly
    printErrors: false
    onFileChanged: reload()
    onLoaded: source.read(text())
    onLoadFailed: source.missing()
  }

  function read(text) {
    var parsed = Notifications.parseLive(text)
    if (!parsed.ok) {
      // Omarchy replaces the file in one step, so this is not a half-written
      // file; it is somebody else's. Keep what is on screen, ask again, and say
      // so once.
      readFailures++
      if (readFailures <= Notifications.RETRIES) retryTimer.restart()
      else if (!warned) {
        console.warn("kalinewb.notch: skipped unreadable notification file " + livePath + " after " + readFailures + " reads")
        warned = true
      }
      return
    }
    readFailures = 0
    warned = false
    if (watchMode === "waiting-file") watchMode = pollOnly ? "poll" : "inotify"
    var listed = ({})
    for (var i = 0; i < parsed.rows.length; i++) {
      listed[parsed.rows[i].key] = true
      changed(parsed.rows[i])
    }
    for (var known in entries) if (listed[known] === undefined) gone(known)
  }

  function missing() {
    for (var name in entries) gone(name, true)
    watchMode = "waiting-file"
  }

  Timer {
    id: retryTimer
    interval: Notifications.RETRY_MS
    onTriggered: if (source.enabled) liveFile.reload()
  }

  Timer {
    id: poll
    running: source.enabled
    repeat: true
    interval: source.watchMode === "inotify" ? Notifications.POLL_MS : Notifications.POLL_ONLY_MS
    onTriggered: liveFile.reload()
  }

  // Turning it off lets go of everything at once: the setting is the whole of
  // the user's part, and a line left behind would outlive the reason for it.
  onEnabledChanged: {
    if (enabled) {
      startedAt = Date.now()
      readFailures = 0
      warned = false
      watchMode = "waiting-file"
      return
    }
    if (bar && bar.platform) bar.platform.releaseOwner("notch.notifications")
    entries = ({})
    watchMode = "waiting-file"
  }

  // Bar-off declines every claim, so nothing is lost when the bar comes back.
  Connections {
    target: source.bar
    ignoreUnknownSignals: true
    function onBarHiddenChanged() {
      if (!source.enabled || source.bar.barHidden) return
      for (var name in source.entries) {
        var e = source.entries[name]
        if (e.dismissed || !e.data || e.state === "dropped" || e.state === "ignored-old" || e.state === "stock") continue
        source.claim(name, e.data)
      }
    }

    // A quiet notch (a plugin asked it to step aside, Bar.qml) is the same for
    // anything that arrived meanwhile. What was already on the queue was never
    // let go of -- only not drawn, with its clock stopped -- so it is left alone.
    function onQuietChanged() {
      if (!source.enabled || source.bar.notchAway) return
      for (var name in source.entries) {
        var e = source.entries[name]
        if (e.dismissed || !e.data || e.state === "dropped" || e.state === "ignored-old" || e.state === "stock") continue
        if (e.state === "shown" || e.state === "queued") continue
        source.claim(name, e.data)
      }
    }
  }

  function report() {
    var list = []
    for (var name in entries) {
      var e = entries[name]
      list.push({ name: name, stamp: e.stamp, state: e.state, key: keyFor(name),
                  dismissed: e.dismissed === true,
                  live: e.live !== false, deadline: Number(e.deadline || 0) })
    }
    list.sort(function(a, b) { return a.stamp - b.stamp })
    return { enabled: enabled, dir: dir, watch: watchMode, startedAt: startedAt,
             claimed: claimedCount(), stay: stay, lifetimeMs: lifetimeMs, pointerOver: pointerOver,
             service: service !== null, entries: list }
  }
}
