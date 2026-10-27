import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "notifications.js" as Notifications

// Omarchy's toasts, shown in the notch.
//
// The notch does not own org.freedesktop.Notifications, never watches the bus,
// never calls CloseNotification and never touches do-not-disturb. Omarchy
// writes one JSON file per live toast into ~/.local/state/omarchy/notifications
// and moves it to history/ when it expires or is dismissed, so watching that
// folder is how a toast is found: a file appearing claims an activity. Omarchy's
// own toast still draws as well, unless "Suppress Omarchy's own toast" is on:
// then the notifications companion (Companion.qml) keeps it off screen while
// this shows it.
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
  readonly property bool enabled: !!bar && bar.notchNotifications && dir !== ""
    && ((!!bar.shell && !bar.harnessed) || forced)

  // When this source came up. A file stamped before it is never read: Omarchy
  // rewrites restored toasts under their old names at restart, so anything
  // older is something the user has already seen.
  property real startedAt: 0

  // name -> { stamp, state, key, parseAttempts, warned, dismissed, live, data, deadline }
  // state: reading | shown | queued | declined:<r> | waiting | dismissed
  //        | closed | dropped | skipped | ignored-old
  // live: the file is still in Omarchy's folder (its toast has not ended).
  // data: what was read from it, kept so the copy outlives the file.
  // deadline: when the timed copy closes (0 until it is on screen).
  property var entries: ({})
  property var readQueue: []
  property string reading: ""
  // inotify | poll | waiting-dir
  property string watchMode: "waiting-dir"
  property int watcherRestarts: 0
  property real watcherStartedAt: 0
  // The two settings: stay until acted on, or close after a number of seconds.
  readonly property bool stay: !!bar && bar.notchNotificationStay
  readonly property int lifetimeMs: Notifications.lifetimeMs(stay, bar ? bar.notchNotificationSeconds : Notifications.SECONDS_DEFAULT)
  // The pointer is over the notch while one is showing: its clock waits.
  readonly property bool pointerOver: {
    var windows = bar ? bar.notchWindows : []
    for (var i = 0; i < windows.length; i++) if (windows[i].pointerOnNotch) return true
    return false
  }
  property bool inotifyMissing: Quickshell.env("NOTCH_NOTIFICATIONS_WATCH") === "poll"

  function keyFor(name) { return "notch.notifications." + Notifications.stem(name) }

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
    setEntry(name, { state: result, key: keyFor(name), data: entry, deadline: 0 })
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
      if (e.state !== "waiting" || e.dismissed) continue
      if (e.stamp > bestStamp) { bestStamp = e.stamp; best = name }
    }
    if (best === "") return
    // One that was on screen already has what it needs; its file may be gone.
    if (entries[best].data) claim(best, entries[best].data)
    else queueRead(best)
  }

  function changed(name) {
    var parsed = Notifications.parseName(name)
    if (!parsed) return
    var existing = entries[name]
    if (existing && existing.dismissed) return
    if (parsed.stamp < startedAt) { setEntry(name, { stamp: parsed.stamp, state: "ignored-old" }); return }
    if (!existing) setEntry(name, { stamp: parsed.stamp, state: "reading", parseAttempts: 0, warned: false, dismissed: false, live: true })
    if (existing && existing.state === "skipped") setEntry(name, { parseAttempts: 0, state: "reading" })
    if (!existing && claimedCount() >= Notifications.OWNER_LIMIT) { setEntry(name, { state: "waiting" }); return }
    queueRead(name)
  }

  // The file left Omarchy's folder: its toast ended, there or here. A copy the
  // notch is showing (or has waiting, having shown it) runs on its own clock and
  // stays as it is -- only its link to Omarchy's toast is gone. Anything else
  // lets go, and so does everything when `force` says the folder itself went.
  function gone(name, force) {
    var e = entries[name]
    if (e === undefined) return
    var keeps = force !== true && (e.state === "shown" || e.state === "queued" || (e.state === "waiting" && e.data))
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
  //     Omarchy's real service: its invokePopupDefault / dismissPopup on the row
  //     for this toast (found by the file's name: timestamp and original id);
  //   - otherwise through Omarchy's `notifications` IPC target, the one its own
  //     keybinds use, which acts on the newest popup (`invokeLast`, `dismissOne`)
  //     or, for a dismissal, one named by its summary;
  //   - a copy whose toast has already ended is no longer in Omarchy's service at
  //     all. Opening it then does what the service would have done with the
  //     toast's own data: run its argv the way Omarchy does, or focus its app
  //     with Omarchy's helper.
  //
  // Answers which way it went: service | ipc | local | notch | no-such-notification.
  readonly property var service: {
    var facade = bar && bar.notificationsCompanion ? bar.notificationsCompanion.facade : null
    var stock = facade ? facade.stockItem : null
    return stock && stock.popupModel && typeof stock.invokePopupDefault === "function" ? stock : null
  }

  function popupIndex(name) {
    var svc = service
    var parsed = Notifications.parseName(name)
    if (!svc || !parsed) return -1
    for (var i = 0; i < svc.popupModel.count; i++) {
      var row = svc.popupModel.get(i)
      if (row && Number(row.originalId) === parsed.id && Number(row.timestamp) === parsed.stamp) return i
    }
    return -1
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
    var index = e.live === false ? -1 : popupIndex(name)
    if (index >= 0) {
      if (open) service.invokePopupDefault(index)
      else service.dismissPopup(index)
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
      if (pointerOver && key === shownKey) { setEntry(name, { deadline: e.deadline + dt }); continue }
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

  function queueRead(name) {
    if (readQueue.indexOf(name) !== -1 || reading === name) return
    var next = readQueue.slice()
    next.push(name)
    readQueue = next
    pumpReads()
  }

  function pumpReads() {
    if (reading !== "" || readQueue.length === 0 || !enabled) return
    var next = readQueue.slice()
    var name = next.shift()
    readQueue = next
    reading = name
    reader.command = ["cat", "--", dir + "/" + name]
    reader.running = true
  }

  function readFinished(name, text) {
    reading = ""
    if (entries[name] === undefined) { pumpReads(); return }
    // Nothing at all means the file went while this was reading it. An empty
    // file is never a toast, so there is nothing to retry for.
    if (String(text).replace(/^\s+|\s+$/g, "") === "") { gone(name); pumpReads(); return }
    var parsed = Notifications.entryFromText(text)
    if (parsed.ok) {
      claim(name, parsed.entry)
      pumpReads()
      return
    }
    // Caught mid-write: Omarchy writes the file and the watch fires on close,
    // but a poll can see it earlier than that.
    var attempts = Number(entries[name].parseAttempts || 0) + 1
    setEntry(name, { parseAttempts: attempts })
    if (attempts <= Notifications.RETRIES) {
      retryTimer.name = name
      retryTimer.restart()
    } else {
      if (!entries[name].warned) {
        console.warn("kalinewb.notch: skipped unreadable notification " + name + " after " + attempts + " reads")
        setEntry(name, { warned: true })
      }
      setEntry(name, { state: "skipped" })
    }
    pumpReads()
  }

  Timer {
    id: retryTimer
    property string name: ""
    interval: Notifications.RETRY_MS
    onTriggered: if (source.enabled && name !== "") source.queueRead(name)
  }

  Process {
    id: reader
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: source.readFinished(source.reading, text)
    }
  }

  // --- what is in the folder ------------------------------------------------
  //
  // The watch can go quiet (a moved folder, a dropped inotify instance), so the
  // listing is the source of truth and the watch is only what makes it prompt.
  // `find` failing must never read as "the folder is empty", or one bad listing
  // would release every live notification. It says so in words instead.
  Process {
    id: lister
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: source.listed(text)
    }
  }

  function listed(text) {
    {
      if (String(text).indexOf("__failed__") !== -1) { dirProbe.running = true; return }
      var listed = ({})
      var lines = String(text).split("\n")
      for (var i = 0; i < lines.length; i++) {
        var name = lines[i].replace(/^\s+|\s+$/g, "")
        if (name === "" || !Notifications.parseName(name)) continue
        listed[name] = true
        if (source.entries[name] === undefined) source.changed(name)
      }
      for (var known in source.entries) if (listed[known] === undefined) source.gone(known)
    }
  }

  Process {
    id: dirProbe
    command: ["sh", "-c", 'test -d "$1" && echo yes || echo no', "sh", source.dir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (String(text).indexOf("yes") === 0) {
          if (source.watchMode === "waiting-dir") {
            source.watcherRestarts = 0
            source.watchMode = source.inotifyMissing ? "poll" : "inotify"
          }
          return
        }
        // The folder is gone: Omarchy's plugin is off, or it has not started
        // yet. Nothing is live, so let go rather than hold stale lines.
        for (var name in source.entries) source.gone(name, true)
        source.watchMode = "waiting-dir"
      }
    }
  }

  Process {
    id: inotifyProbe
    command: ["sh", "-c", "command -v inotifywait >/dev/null && echo yes || echo no"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: source.inotifyMissing = String(text).indexOf("yes") !== 0
        || Quickshell.env("NOTCH_NOTIFICATIONS_WATCH") === "poll"
    }
  }

  Process {
    id: watcher
    running: source.enabled && source.watchMode === "inotify"
    command: ["inotifywait", "-m", "-q", "-e", "close_write,moved_to,moved_from,delete", "--format", "%e %f", source.dir]
    stdout: SplitParser {
      onRead: function(line) {
        var text = String(line)
        var space = text.indexOf(" ")
        if (space === -1) return
        var flags = text.slice(0, space).split(",")
        var name = text.slice(space + 1)
        if (flags.indexOf("ISDIR") !== -1) return
        var first = flags[0]
        if (first === "CLOSE_WRITE" || first === "MOVED_TO") source.changed(name)
        else if (first === "DELETE" || first === "MOVED_FROM") source.gone(name)
      }
    }
    onRunningChanged: {
      if (running) { source.watcherStartedAt = Date.now(); return }
      if (!source.enabled || source.watchMode !== "inotify") return
      // A watcher that ran a good while and then died is a fresh problem, not
      // a folder that was never there: give it its restarts back.
      if (Date.now() - source.watcherStartedAt > 60000) source.watcherRestarts = 0
      source.watcherRestarts++
      if (source.watcherRestarts > 5) { source.watchMode = "poll"; return }
      source.watchMode = "waiting-dir"
      dirProbe.running = true
    }
  }

  Timer {
    id: poll
    running: source.enabled
    repeat: true
    interval: source.watchMode === "inotify" ? Notifications.POLL_MS : Notifications.POLL_ONLY_MS
    triggeredOnStart: true
    onTriggered: {
      if (source.watchMode === "waiting-dir") { dirProbe.running = true; return }
      if (!lister.running) {
        lister.command = ["sh", "-c",
          'find "$1" -maxdepth 1 -type f -name "*.json" -printf "%f\\n" 2>/dev/null || echo __failed__',
          "sh", source.dir]
        lister.running = true
      }
      // A watcher that dropped to polling gets a chance to come back.
      if (source.watchMode === "poll" && !source.inotifyMissing) source.watchMode = "inotify"
    }
  }

  // Turning it off lets go of everything at once: the setting is the whole of
  // the user's part, and a line left behind would outlive the reason for it.
  onEnabledChanged: {
    if (enabled) {
      startedAt = Date.now()
      watcherRestarts = 0
      watchMode = "waiting-dir"
      inotifyProbe.running = true
      dirProbe.running = true
      return
    }
    if (bar && bar.platform) bar.platform.releaseOwner("notch.notifications")
    entries = ({})
    readQueue = []
    reading = ""
    watchMode = "waiting-dir"
  }

  // Bar-off declines every claim, so nothing is lost when the bar comes back.
  Connections {
    target: source.bar
    ignoreUnknownSignals: true
    function onBarHiddenChanged() {
      if (!source.enabled || source.bar.barHidden) return
      for (var name in source.entries) {
        var e = source.entries[name]
        if (e.dismissed || e.state === "dropped" || e.state === "skipped" || e.state === "ignored-old") continue
        source.queueRead(name)
      }
    }
  }

  function report() {
    var list = []
    for (var name in entries) {
      var e = entries[name]
      list.push({ name: name, stamp: e.stamp, state: e.state, key: keyFor(name),
                  attempts: Number(e.parseAttempts || 0), dismissed: e.dismissed === true,
                  live: e.live !== false, deadline: Number(e.deadline || 0) })
    }
    list.sort(function(a, b) { return a.stamp - b.stamp })
    return { enabled: enabled, dir: dir, watch: watchMode, startedAt: startedAt,
             claimed: claimedCount(), stay: stay, lifetimeMs: lifetimeMs, pointerOver: pointerOver,
             service: service !== null, entries: list }
  }
}
