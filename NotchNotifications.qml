import QtQuick
import Quickshell
import Quickshell.Io
import "notifications.js" as Notifications

// Omarchy's toasts, shown in the notch.
//
// A display surface and nothing else. The notch does not own
// org.freedesktop.Notifications, never watches the bus, never calls
// CloseNotification and never touches do-not-disturb. Omarchy writes one JSON
// file per live toast into ~/.local/state/omarchy/notifications and moves it to
// history/ when it expires or is dismissed, so watching that folder is the
// whole mechanism: a file appearing claims an activity, the file leaving
// releases it. Omarchy's own toast still draws as well -- both show in v1.
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

  // name -> { stamp, state, key, parseAttempts, warned, dismissed }
  // state: reading | shown | queued | declined:<r> | waiting | dismissed
  //        | dropped | skipped | ignored-old
  property var entries: ({})
  property var readQueue: []
  property string reading: ""
  // inotify | poll | waiting-dir
  property string watchMode: "waiting-dir"
  property int watcherRestarts: 0
  property real watcherStartedAt: 0
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
    var result = bar.platform.claimInternal("notch.notifications", Notifications.claimFor(name, entry))
    setEntry(name, { state: result, key: keyFor(name) })
    if (result.indexOf("declined") === 0) return
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
    if (best !== "") queueRead(best)
  }

  function changed(name) {
    var parsed = Notifications.parseName(name)
    if (!parsed) return
    var existing = entries[name]
    if (existing && existing.dismissed) return
    if (parsed.stamp < startedAt) { setEntry(name, { stamp: parsed.stamp, state: "ignored-old" }); return }
    if (!existing) setEntry(name, { stamp: parsed.stamp, state: "reading", parseAttempts: 0, warned: false, dismissed: false })
    if (existing && existing.state === "skipped") setEntry(name, { parseAttempts: 0, state: "reading" })
    if (!existing && claimedCount() >= Notifications.OWNER_LIMIT) { setEntry(name, { state: "waiting" }); return }
    queueRead(name)
  }

  function gone(name) {
    if (entries[name] === undefined) return
    release(name)
    dropEntry(name)
    promoteWaiting()
  }

  // Nothing is written and nothing is sent to Omarchy: dismissing clears the
  // notch's copy only, and Omarchy's own toast runs its own course.
  function dismiss(key) {
    for (var name in entries) {
      if (keyFor(name) !== key) continue
      release(name)
      setEntry(name, { dismissed: true, state: "dismissed" })
      promoteWaiting()
      return true
    }
    return false
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
        console.warn("graveklar.notch: skipped unreadable notification " + name + " after " + attempts + " reads")
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
        for (var name in source.entries) source.gone(name)
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
                  attempts: Number(e.parseAttempts || 0), dismissed: e.dismissed === true })
    }
    list.sort(function(a, b) { return a.stamp - b.stamp })
    return { enabled: enabled, dir: dir, watch: watchMode, startedAt: startedAt,
             claimed: claimedCount(), entries: list }
  }
}
