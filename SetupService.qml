import QtQuick
import Quickshell
import Quickshell.Io

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

  readonly property var points: {
    var base = (report && report.points) ? report.points : []
    var mine = inProcessPoints()
    if (!mine.length) return base
    var merged = []
    for (var i = 0; i < base.length; i++) {
      var replacement = null
      for (var j = 0; j < mine.length; j++) if (mine[j].id === base[i].id) replacement = mine[j]
      merged.push(replacement || base[i])
    }
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

  function status() {
    return {
      enabled: enabled, checking: checking, checkedAt: checkedAt, issueCount: issueCount,
      counts: (report && report.counts) ? report.counts : {},
      context: (report && report.context) ? report.context : {},
      points: points, job: job || {}, snapshots: snapshots,
      statusPath: statusPath, waiting: waitingForJob, pendingReopen: pendingReopen
    }
  }
}
