import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// What Setup knows, and how it starts a job.
//
// Everything that changes anything lives in bin/notch-setup. This owns the
// reading side: it runs `detect --json`, watches the status file a running job
// writes, and launches fixes and restores detached -- detached because a fix
// can reload every plugin, which destroys the notch that started it. The
// rebuilt notch then reads the same status file and reopens the page with the
// result.
//
// A test notch doesn't do any of this unless NOTCH_FORCE_SETUP=1, the same rule
// the update feature follows: without it the live status file is never read,
// never written, and no job is ever started.
Item {
  id: root
  visible: false

  required property var bar

  readonly property bool enabled: (!!bar.shell && !bar.harnessed) || Quickshell.env("NOTCH_FORCE_SETUP") === "1"
  readonly property string script: String(Qt.resolvedUrl("bin/notch-setup")).replace(/^file:\/\//, "")
  readonly property string statusPath: Quickshell.env("NOTCH_SETUP_STATUS")
    || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/graveklar.notch/setup.json")

  // The last `detect --json`, plus the points only the running notch can see.
  property var report: ({})
  property bool checking: false
  property var job: ({})
  property var snapshots: []
  property real checkedAt: 0
  property real lastFullCheck: 0

  // The script's list, with the notch's own findings laid over it: a point the
  // script also knows about is replaced in place, keeping the script's order,
  // and one only the notch can see is appended. Appending matters -- a point
  // with no counterpart in the script used to be dropped, which meant it could
  // never appear at all.
  readonly property var points: {
    var base = (report && report.points) ? report.points : []
    var mine = inProcessPoints()
    if (!mine.length) return base
    var used = ({})
    var merged = []
    for (var i = 0; i < base.length; i++) {
      var replacement = null
      for (var j = 0; j < mine.length; j++) {
        if (mine[j].id !== base[i].id) continue
        replacement = mine[j]
        used[mine[j].id] = true
      }
      merged.push(replacement || base[i])
    }
    for (var k = 0; k < mine.length; k++) if (!used[mine[k].id]) merged.push(mine[k])
    return merged
  }

  readonly property int issueCount: {
    var n = 0
    for (var i = 0; i < points.length; i++) {
      var severity = points[i].severity
      if (severity === "fix" || severity === "action" || severity === "warn") n++
    }
    return n
  }

  readonly property bool jobRunning: {
    var phase = (job || {}).phase || ""
    return phase !== "" && phase !== "done" && phase !== "failed" && phase !== "rolled-back"
      && phase !== "conflict" && phase !== "locked-out"
  }

  // --- what only this notch can check -------------------------------------------------

  // A widget in the layout that drew nothing. The notch heals this once by
  // itself; what's left after that is worth telling the user about.
  function inProcessPoints() {
    var points = emptyWidgetPoint()
    points.push(themeTokensPoint())
    var companion = menuCompanionPoint()
    if (companion) points.push(companion)
    return points
  }

  // Omarchy creates a menu plugin's entry point when the menu is opened and
  // drops it again afterwards, so `active: false` in the plugin list means
  // "the menu is shut" far more often than "it failed to load".
  // bin/notch-setup runs outside the shell and has nothing better to go on, so
  // it reported a perfectly good companion as broken. The notch does know: its
  // bridge either has the companion's facade or it does not. This corrects the
  // script's verdict, and only ever downwards -- when the notch is not happy
  // either, the script's point stands as it is.
  function menuCompanionPoint() {
    if (!bar || !bar.menuCompanion || !bar.notchReplaceMenu) return null
    if (bar.menuCompanion.companionState !== "active") return null
    return { id: "menu-replace-companion", severity: "ok", title: "The menu opens in the notch",
             summary: "The companion is installed, enabled and talking to this notch.",
             detail: [], items: [], fix: null, handoff: null }
  }

  // A theme can pin selection, hover and focus fills to a colour of its own
  // (`selected-color = "accent"`, or a hex, in its style section -- Catppuccin
  // Latte pins all four to #4c4f69). A panel the notch hosts hands Style's
  // helpers the notch's white, but such a token makes the helper ignore what
  // it was handed -- the one way a theme colour still gets inside the notch.
  // Only the notch can see the resolved tokens.
  function themeTokensPoint() {
    var tokens = { "normal-color": Style.normalColorToken, "hover-cursor-color": Style.hoverColorToken,
                   "selected-color": Style.selectedColorToken, "pressed-color": Style.pressedColorToken,
                   "focus-color": Style.focusColorToken, "selection-color": Style.selectionColorToken }
    var off = []
    for (var key in tokens) {
      var role = String(tokens[key] || "").replace(/^\s+|\s+$/g, "").toLowerCase()
      if (role !== "foreground" && role !== "text" && role !== "transparent" && role !== "") off.push({ arg: key, summary: key + " = \"" + tokens[key] + "\"" })
    }
    if (!off.length) {
      return { id: "theme-tokens", severity: "ok", title: "Your theme keeps its colours out of the notch",
               summary: "Its style tokens resolve to the text colour, so a panel the notch draws paints white.", detail: [], items: [], fix: null, handoff: null }
    }
    return {
      id: "theme-tokens", severity: "info",
      title: "Your theme tints panels drawn inside the notch",
      summary: "When a plugin's panel opens inside the notch, its hover highlights, selection and outlines come out in your theme's colour instead of white. The notch's own switches and buttons are unaffected. Nothing to press: it is decided by " + off.length + " colour(s) your theme pins, which the notch cannot override for itself alone.",
      detail: ["The notch paints in white only, but a plugin's own panel asks Omarchy's Style helpers for its fills, and these tokens tell the helper to use the theme's colour instead of the white it was handed. Those helpers are shared with the whole desktop, so the notch cannot change them just for itself.",
               "If it bothers you: set them to \"foreground\" in the theme's shell.toml [style] section, or pick a theme that leaves them at the default. That changes them everywhere, not only in the notch. Text is unaffected either way."],
      items: off, fix: null, handoff: null
    }
  }

  function emptyWidgetPoint() {
    if (!bar || typeof bar.emptyWidgetIds !== "function") return []
    var ids = bar.emptyWidgetIds()
    if (!ids || !ids.length) {
      return [{ id: "layout-empty-widget", severity: "ok", title: "Every widget drew something",
                summary: "No widget in the bar is empty.", detail: [], items: [], fix: null, handoff: null }]
    }
    var items = []
    for (var i = 0; i < ids.length; i++) items.push({ arg: ids[i], summary: ids[i] + " drew nothing" })
    return [{ id: "layout-empty-widget", severity: "fix", title: "A widget in the bar is empty",
              summary: ids.join(", ") + " loaded but drew nothing.",
              detail: ["Fix restarts the shell, which loads every plugin again.",
                       "The notch closes while that happens and this page comes back with the result."],
              items: items,
              fix: { kind: "runtime", label: "Fix", files: [], reload: [], risk: "medium",
                     destroysNotch: true, disabledReason: "" },
              handoff: null }]
  }

  // --- reading ------------------------------------------------------------------------

  // check(local): `--local` skips the network (the plugin installer's state
  // fetches), so opening the page shows something at once.
  function check(localOnly) {
    if (!enabled || checkProcess.running) return false
    checkProcess.command = localOnly ? [script, "detect", "--json", "--local"] : [script, "detect", "--json"]
    checkProcess.localOnly = localOnly === true
    checkProcess.running = true
    checking = true
    return true
  }

  function refreshSnapshots() {
    if (!enabled || snapshotProcess.running) return false
    snapshotProcess.running = true
    return true
  }

  Process {
    id: checkProcess
    property bool localOnly: false
    command: [root.script, "detect", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.report = JSON.parse(text) } catch (e) { root.report = { points: [], counts: {} } }
        root.checkedAt = Date.now()
        if (!checkProcess.localOnly) root.lastFullCheck = root.checkedAt
        root.checking = false
        root.refreshSnapshots()
      }
    }
    onRunningChanged: if (!running) root.checking = false
  }

  Process {
    id: snapshotProcess
    command: [root.script, "snapshots", "--json"]
    stdout: StdioCollector {
      onStreamFinished: { try { root.snapshots = JSON.parse(text) } catch (e) { root.snapshots = [] } }
    }
  }

  // --- starting a job ------------------------------------------------------------------

  // Built the way startUpdate() builds its argv: a transient unit when systemd
  // is there, so the job outlives the notch that started it.
  function detachedArgv(run) {
    if ((Quickshell.env("NOTCH_SETUP_DETACH") || "systemd-run") !== "systemd-run") return ["setsid", "-f"].concat(run)
    var argv = ["systemd-run", "--user", "--collect", "--quiet", "--unit", "graveklar-notch-setup-" + Date.now()]
    var passed = ["PATH", "HOME", "OMARCHY_PATH", "HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY",
                  "XDG_RUNTIME_DIR", "XDG_STATE_HOME", "XDG_CONFIG_HOME",
                  "NOTCH_SETUP_SANDBOX", "NOTCH_SETUP_HOME", "NOTCH_SETUP_CONFIG_DIR", "NOTCH_SETUP_TOGGLES_DIR",
                  "NOTCH_SETUP_STATE_DIR", "NOTCH_SETUP_STATUS", "NOTCH_SETUP_OMARCHY_PATH", "NOTCH_SETUP_PLUGINS_DIR",
                  "NOTCH_SETUP_NOTCH_DIR", "NOTCH_SETUP_HYPRCTL", "NOTCH_SETUP_OMARCHY_SHELL", "NOTCH_SETUP_OMARCHY",
                  "NOTCH_SETUP_OMARCHY_VERSION", "NOTCH_SETUP_TOGGLE_BAR", "NOTCH_SETUP_QS", "NOTCH_SETUP_KILL",
                  "NOTCH_SETUP_LUA", "NOTCH_SETUP_PLUGINS_STATE", "NOTCH_SETUP_SESSION_LOCKED",
                  "NOTCH_SETUP_RESTART_SHELL", "NOTCH_SETUP_PROC", "NOTCH_SETUP_RETENTION_DAYS",
                  "NOTCH_SETUP_RETENTION_CAP", "NOTCH_SETUP_FAIL_AT"]
    for (var i = 0; i < passed.length; i++) {
      var value = Quickshell.env(passed[i])
      if (value) argv.push("--setenv=" + passed[i] + "=" + value)
    }
    return argv.concat(run)
  }

  function pointById(id) {
    for (var i = 0; i < points.length; i++) if (points[i].id === id) return points[i]
    return null
  }

  function startFix(id, arg) {
    if (!enabled || jobRunning) return false
    var point = pointById(id)
    var run = [script, "fix", id, "--status", statusPath]
    if (arg) run = run.concat(["--arg", String(arg)])
    if (point && point.fix && point.fix.destroysNotch) run.push("--reopen")
    job = { phase: "snapshotting", action: "fix", point: id, arg: String(arg || ""),
            startedAt: Date.now(), finishedAt: 0, seen: false, launched: true }
    Quickshell.execDetached(detachedArgv(run))
    statusPoll.restart()
    return true
  }

  // mode: "" | "force" | "block-only"
  function startRestore(name, mode) {
    if (!enabled || jobRunning) return false
    var run = [script, "restore", name, "--status", statusPath]
    if (mode === "force") run.push("--force")
    else if (mode === "block-only") run.push("--block-only")
    // A raw shell.json restore rescans plugins, which takes the notch with it.
    var snapshot = snapshotByName(name)
    if (snapshot && snapshot.kind === "ipc") run.push("--reopen")
    job = { phase: "applying", action: "restore", point: (snapshot ? snapshot.point : ""), snapshot: name,
            startedAt: Date.now(), finishedAt: 0, seen: false, launched: true }
    Quickshell.execDetached(detachedArgv(run))
    statusPoll.restart()
    return true
  }

  function forget(name) {
    if (!enabled) return false
    Quickshell.execDetached([script, "forget", name])
    forgetTimer.restart()
    return true
  }

  function snapshotByName(name) {
    for (var i = 0; i < snapshots.length; i++) if (snapshots[i].name === name) return snapshots[i]
    return null
  }

  function ack() {
    if (!enabled) return false
    var copy = JSON.parse(JSON.stringify(job || {}))
    copy.seen = true
    job = copy
    Quickshell.execDetached([script, "ack", statusPath])
    return true
  }

  Timer { id: forgetTimer; interval: 400; onTriggered: root.refreshSnapshots() }

  // --- the status file, and coming back after a job destroyed the notch ------------------

  property bool startupRead: false
  property bool waitingForJob: false
  property bool pendingReopen: false
  property real reopenDeadline: 0
  property real windowDeadline: 0
  property int deadProbes: 0

  FileView {
    id: statusFile
    path: root.enabled ? root.statusPath : ""
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var parsed = {}
      try { parsed = JSON.parse(text()) } catch (e) { parsed = {} }
      root.job = parsed
      if (!root.startupRead) {
        root.startupRead = true
        // A job that asked for the page to come back, started moments ago and
        // not yet seen: this notch is the one it was destroyed for.
        if (parsed.reopen === true && parsed.seen !== true && Date.now() - Number(parsed.startedAt || 0) < 60000) {
          root.waitingForJob = true
          root.reopenDeadline = Number(parsed.startedAt || 0) + 60000
          root.deadProbes = 0
        }
        return
      }
      if (!root.waitingForJob) return
      if (!root.jobRunning) {
        // Final. The page opens for a failure too: that is where the reason is.
        if (parsed.reopen === true) { root.pendingReopen = true; root.windowDeadline = Date.now() + 5000 }
        root.waitingForJob = false
      } else if (Date.now() > root.reopenDeadline) {
        root.waitingForJob = false
      }
    }
  }

  Timer {
    id: statusPoll
    interval: 1000
    repeat: true
    running: root.enabled && (root.jobRunning || root.waitingForJob)
    onTriggered: {
      statusFile.reload()
      if (root.waitingForJob && root.jobRunning) pidProbe.running = true
    }
  }

  // A job can die without writing its last word (an OOM kill, `systemctl stop`).
  // Two probes in a row with no process and no final write mean it is gone.
  //
  // `test -d` prints nothing and says everything in its exit code, so the probe
  // prints the answer instead and the collector reads it.
  Process {
    id: pidProbe
    command: ["sh", "-c", "test -d /proc/$1 && echo alive || echo gone", "probe", String(Number((root.job || {}).pid || 0))]
    stdout: StdioCollector {
      onStreamFinished: {
        if (!root.waitingForJob) return
        if (text.indexOf("alive") !== -1) { root.deadProbes = 0; return }
        root.deadProbes++
        if (root.deadProbes >= 2) {
          root.waitingForJob = false
          root.pendingReopen = true
          root.windowDeadline = Date.now() + 5000
          var copy = JSON.parse(JSON.stringify(root.job || {}))
          copy.phase = "failed"
          copy.message = "The job stopped before it finished. Check Snapshots."
          root.job = copy
        }
      }
    }
  }

  // The window may not exist yet when the reopen is decided: QML doesn't
  // promise the order siblings complete in, so this waits for one.
  Timer {
    id: reopenTimer
    interval: 100
    repeat: true
    running: root.enabled && root.pendingReopen
    onTriggered: {
      var window = root.bar.focusedNotchWindow()
      if (window) {
        window.openSetup()
        root.pendingReopen = false
        root.ack()
      } else if (Date.now() > root.windowDeadline) {
        root.pendingReopen = false
      }
    }
  }

  function report_() { return report }

  // Tallied over the merged points, so the counts describe what the page
  // shows -- the script's own tally does not know the in-process points.
  function countsOf(list) {
    var out = ({})
    for (var i = 0; i < list.length; i++) { var s = list[i].severity || "unknown"; out[s] = (out[s] || 0) + 1 }
    return out
  }

  function status() {
    return {
      enabled: enabled, checking: checking, checkedAt: checkedAt, issueCount: issueCount,
      counts: countsOf(points),
      context: (report && report.context) ? report.context : {},
      points: points, job: job || {}, snapshots: snapshots,
      statusPath: statusPath, waiting: waitingForJob, pendingReopen: pendingReopen
    }
  }
}
