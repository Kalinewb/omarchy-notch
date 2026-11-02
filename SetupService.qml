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
    || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/kalinewb.notch/setup.json")

  // The last `detect --json`, plus the points only the running notch can see.
  property var report: ({})
  property bool checking: false
  // The last check could not be read: the script did not answer, or what it
  // printed was not a report. `report` keeps the last good one, and the page
  // says "Couldn't check" instead of "everything is working".
  property bool checkFailed: false
  property var job: ({})
  property var snapshots: []
  property real checkedAt: 0
  property real lastFullCheck: 0

  // What needs attention: the script's list, with the notch's own findings
  // laid over it. Only the notch can see an empty bar widget, and only its
  // bridge knows a menu helper is talking to it (below).
  readonly property var points: {
    var base = (report && report.points) ? report.points : []
    var out = []
    for (var i = 0; i < base.length; i++) {
      var id = base[i].id
      if (id === "layout-empty-widget") continue
      if (id === "menu-replace-companion" && menuHelperWorks()) continue
      // The notch is still trying to set a helper up by itself: not a problem yet.
      if ((id === "menu-replace-companion" || id === "osd-companion") && helperWorking(id)) continue
      out.push(base[i])
    }
    var empty = emptyWidgetPoint()
    if (empty) out.push(empty)
    return out
  }

  readonly property int issueCount: points.length

  readonly property bool jobRunning: {
    var phase = (job || {}).phase || ""
    return phase !== "" && phase !== "done" && phase !== "failed" && phase !== "rolled-back"
      && phase !== "conflict" && phase !== "locked-out"
  }

  // --- what only this notch can check -------------------------------------------------

  // Omarchy creates a menu plugin's entry point when the menu is opened and
  // drops it again afterwards, so `active: false` in the plugin list means
  // "the menu is shut" far more often than "it failed to load". The notch does
  // know: its bridge either has the companion's facade or it does not.
  function menuHelperWorks() {
    return !!bar && !!bar.menuCompanion && !!bar.notchReplaceMenu && bar.menuCompanion.companionState === "active"
  }
  function helperWorking(id) {
    var helper = !bar ? null : id === "osd-companion" ? bar.osdCompanion : bar.menuCompanion
    return !!helper && helper.statusKey === "working"
  }

  // A widget in the layout that drew nothing. The notch heals this once by
  // itself; what's left after that is worth telling the user about.
  function emptyWidgetPoint() {
    if (!bar || typeof bar.emptyWidgetIds !== "function") return null
    var ids = bar.emptyWidgetIds()
    if (!ids || !ids.length) return null
    var items = []
    for (var i = 0; i < ids.length; i++) items.push({ arg: ids[i], summary: ids[i] })
    return { id: "layout-empty-widget", severity: "fix", admit: "page",
             title: ids.length === 1 ? "A bar item shows nothing" : ids.length + " bar items show nothing",
             summary: "Restarting the bar usually fixes it. The notch closes for a moment.",
             detail: [], items: items,
             fix: { kind: "runtime", label: "Restart bar", files: [], reload: [], risk: "medium", destroysNotch: true, disabledReason: "" },
             handoff: null }
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

  // "Try again" on a helper row: the notch asks the companion's installer once
  // more (Companion.setUp), then looks again when it has had time to finish.
  function retryHelper(which) {
    var helper = which === "osd" ? bar.osdCompanion : which === "notifications" ? bar.notificationsCompanion : bar.menuCompanion
    if (!enabled || !helper || !helper.setUp()) return false
    recheck.restart()
    return true
  }
  Timer { id: recheck; interval: 15000; onTriggered: root.check(false) }

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
        var parsed = null
        try { parsed = JSON.parse(text) } catch (e) { parsed = null }
        root.checkFailed = !parsed || !Array.isArray(parsed.points)
        if (!root.checkFailed) {
          root.report = parsed
          root.checkedAt = Date.now()
          if (!checkProcess.localOnly) root.lastFullCheck = root.checkedAt
        }
        root.checking = false
        root.refreshSnapshots()
      }
    }
    // A script that never started prints nothing and never finishes its stream.
    onRunningChanged: if (!running) Qt.callLater(function() { if (root.checking) { root.checkFailed = true; root.checking = false } })
  }

  Process {
    id: snapshotProcess
    command: [root.script, "snapshots", "--json"]
    stdout: StdioCollector {
      onStreamFinished: { try { root.snapshots = JSON.parse(text) } catch (e) { root.snapshots = [] } }
    }
  }

  // --- starting a job ------------------------------------------------------------------

  Detached { id: detached }
  readonly property var detachedEnv: ["NOTCH_SETUP_SANDBOX", "NOTCH_SETUP_HOME", "NOTCH_SETUP_CONFIG_DIR", "NOTCH_SETUP_TOGGLES_DIR",
    "NOTCH_SETUP_STATE_DIR", "NOTCH_SETUP_STATUS", "NOTCH_SETUP_OMARCHY_PATH", "NOTCH_SETUP_PLUGINS_DIR",
    "NOTCH_SETUP_NOTCH_DIR", "NOTCH_SETUP_HYPRCTL", "NOTCH_SETUP_OMARCHY_SHELL", "NOTCH_SETUP_OMARCHY",
    "NOTCH_SETUP_OMARCHY_VERSION", "NOTCH_SETUP_TOGGLE_BAR", "NOTCH_SETUP_QS", "NOTCH_SETUP_KILL",
    "NOTCH_SETUP_LUA", "NOTCH_SETUP_PLUGINS_STATE", "NOTCH_SETUP_SESSION_LOCKED",
    "NOTCH_SETUP_RESTART_SHELL", "NOTCH_SETUP_PROC", "NOTCH_SETUP_RETENTION_DAYS",
    "NOTCH_SETUP_RETENTION_CAP", "NOTCH_SETUP_FAIL_AT"]
  // Detached (Detached.qml), so the job outlives the notch it may destroy.
  function launch(run) { detached.launch("kalinewb-notch-setup", run, detachedEnv, "NOTCH_SETUP_DETACH") }

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
    launch(run)
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
    launch(run)
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
    // No status file until the first fix runs; that is the normal state.
    printErrors: false
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
      enabled: enabled, checking: checking, checkFailed: checkFailed, checkedAt: checkedAt, issueCount: issueCount,
      counts: countsOf(points),
      context: (report && report.context) ? report.context : {},
      points: points, job: job || {}, snapshots: snapshots,
      statusPath: statusPath, waiting: waitingForJob, pendingReopen: pendingReopen
    }
  }
}
