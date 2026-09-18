import QtQuick
import Quickshell
import Quickshell.Io
import "bridge"

// Everything about the menu companion, the small plugin that lets the notch be
// the Omarchy menu (see README, "Replace the Omarchy menu").
//
// Omarchy sends every menu call -- SUPER + SPACE, `omarchy menu`, the bar's
// menu button, every select/input picker -- to whichever enabled plugin says
// `clonedFrom: omarchy.menu`. That plugin is companion/graveklar.notch-menu,
// installed once into ~/.config/omarchy/plugins. Its go-between asks the notch
// to take the request; when the notch declines (the setting is off, the bar is
// hidden, no notch is running) it opens Omarchy's own menu instead.
//
// This file owns:
//   - menuApi, the only object the companion can reach the notch through
//   - the companion folder's state, and the jobs that install or update it
//
// The jobs change the plugins folder, which reloads every plugin and destroys
// this notch, so they run detached and report through a status file outside
// that folder, exactly as bin/notch-update does.
Item {
  id: companion
  visible: false

  // The notch's Bar.qml root.
  property var bar: null

  // --- what the companion may do to the notch ----------------------------------
  //
  // Not the Bar root: anything that loads bridge/Connector.qml can read
  // NotchMenuBridge.target, and the root carries the notch's shell facade,
  // its settings writer and its updater. This object can only open, close and
  // refresh the menu, and say whether it is open.
  readonly property QtObject menuApi: QtObject {
    function openMenuPayload(payloadJson) {
      return !!companion.bar && companion.bar.openMenuPayload(payloadJson) === true
    }
    function closeMenus() { if (companion.bar) companion.bar.closeMenus() }
    function refreshMenus() { if (companion.bar) companion.bar.refreshMenus() }
    readonly property bool anyMenuOpen: !!companion.bar && companion.bar.anyMenuOpen
    readonly property bool notchReplaceMenu: !!companion.bar && companion.bar.notchReplaceMenu
    readonly property bool barHidden: !!companion.bar && companion.bar.barHidden
  }

  // The notch's own copy of the companion, and the API it speaks.
  readonly property string version: "1.0.0"
  readonly property bool bridged: NotchMenuBridge.target === menuApi
  readonly property string facadeRoute: NotchMenuBridge.facade ? String(NotchMenuBridge.facade.route || "") : ""

  // Only a hosted notch installs or updates anything; a test notch reports and
  // does nothing (NOTCH_FORCE_COMPANION=1 lets dev/menu-replace.sh opt in).
  readonly property bool actionsEnabled: !!bar && ((!!bar.shell && !bar.harnessed) || Quickshell.env("NOTCH_FORCE_COMPANION") === "1")

  readonly property string script: String(Qt.resolvedUrl("bin/notch-companion")).replace(/^file:\/\//, "")
  readonly property string statusPath: (Quickshell.env("NOTCH_COMPANION_STATE_DIR")
    || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/graveklar.notch")) + "/companion.json"

  // The last `notch-companion status` line: what is installed, and whether it
  // matches the copy in this notch.
  property var installed: ({})
  property var job: ({})
  property real dismissedAt: 0
  property real clock: Date.now()

  //   absent    the companion isn't installed
  //   disabled  installed, but switched off in Omarchy
  //   outdated  there, but speaks another API version, carries another version,
  //             or its files differ from this notch's copy
  //   active    there and matching
  //
  // What is on disk is the answer, not whether the go-between happens to be
  // loaded: Omarchy creates a menu plugin's entry point when the menu is opened
  // and drops it afterwards, so "has it registered with the bridge" says
  // "absent" for a perfectly good companion every moment the menu is shut. A
  // live facade is still worth having -- it is the only thing that can report
  // the running API and version -- so it is used when it is there.
  readonly property string companionState: {
    var facade = NotchMenuBridge.facade
    var info = installed || {}
    if (facade) {
      var sameApi = Number(facade.apiVersion) === NotchMenuBridge.apiVersion
      var sameVersion = String(facade.version || "") === version
      if (!sameApi || !sameVersion || info.inSync === false) return "outdated"
      return "active"
    }
    if (info.installed !== true) return "absent"
    if (info.enabled === false) return "disabled"
    if (info.inSync === false) return "outdated"
    return "active"
  }

  // One word for the settings row and the report.
  readonly property string statusKey: {
    var now = clock
    var j = job || {}
    if (j.phase === "working" && now - Number(j.startedAt || 0) < 5 * 60000) return "working"
    if (j.phase === "failed" && Number(j.finishedAt || 0) > dismissedAt) return "failed"
    if (companionState !== "active") return companionState
    if (bar && bar.notchReplaceMenu && bar.barHidden) return "hidden-bar"
    return bar && bar.notchReplaceMenu ? "active-on" : "active-off"
  }

  function dismiss() { dismissedAt = Date.now(); clock = Date.now() }

  // The switch is the whole of the user's part. Whatever the companion folder
  // needs to match it -- installing, enabling, bringing up to date -- the notch
  // does by itself, once per state it finds: a job that failed is not retried
  // until the switch changes or the notch restarts, and Setup reports it.
  property string keptInStep: ""
  function keepInStep() {
    if (!actionsEnabled || !bar || !bar.notchReplaceMenu) { keptInStep = ""; return }
    var state = companionState
    if (state !== "absent" && state !== "disabled" && state !== "outdated") return
    if (statusKey === "working" || keptInStep === state) return
    keptInStep = state
    startJob(state === "outdated" ? "sync" : "install")
  }
  onInstalledChanged: keepInStep()
  Connections {
    target: companion.bar
    function onNotchReplaceMenuChanged() { companion.keptInStep = ""; companion.keepInStep() }
  }

  function setUp() { return startJob("install") }
  function update() { return startJob("sync") }
  function remove() { return startJob("remove") }

  // Detached, in its own systemd user unit: the job reloads every plugin and
  // takes this notch down with it (see bin/notch-update's startUpdate).
  function startJob(verb) {
    if (!actionsEnabled || statusKey === "working") return false
    var run = [script, verb, statusPath]
    var argv
    if ((Quickshell.env("NOTCH_UPDATE_DETACH") || "systemd-run") === "systemd-run") {
      argv = ["systemd-run", "--user", "--collect", "--quiet", "--unit", "graveklar-notch-companion-" + Date.now()]
      var passed = ["PATH", "HOME", "OMARCHY_PATH", "HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR",
                    "XDG_STATE_HOME", "NOTCH_COMPANION_DIR", "NOTCH_COMPANION_SOURCE", "NOTCH_COMPANION_LIST",
                    "NOTCH_COMPANION_ENABLE", "NOTCH_COMPANION_REMOVE", "NOTCH_COMPANION_VALIDATE",
                    "NOTCH_COMPANION_SESSION_LOCKED", "NOTCH_COMPANION_STATE_DIR"]
      for (var i = 0; i < passed.length; i++) {
        var value = Quickshell.env(passed[i])
        if (value) argv.push("--setenv=" + passed[i] + "=" + value)
      }
      argv = argv.concat(run)
    } else {
      argv = ["setsid", "-f"].concat(run)
    }
    job = { phase: "working", verb: verb, startedAt: Date.now(), finishedAt: 0, message: "", launched: true }
    clock = Date.now()
    Quickshell.execDetached(argv)
    statusPoll.restart()
    return true
  }

  function readStatus() {
    if (!actionsEnabled || statusProcess.running) return false
    statusProcess.running = true
    return true
  }

  Process {
    id: statusProcess
    command: [companion.script, "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { companion.installed = JSON.parse(text) } catch (e) { companion.installed = {} }
      }
    }
  }

  FileView {
    id: jobFile
    path: companion.actionsEnabled ? companion.statusPath : ""
    printErrors: false
    onLoaded: {
      try {
        var next = JSON.parse(text())
        if (next && next.phase && !(companion.job.launched && Number(next.startedAt || 0) < Number(companion.job.startedAt || 0) - 2000)) {
          var finished = companion.job.phase === "working" && (next.phase === "done" || next.phase === "failed")
          companion.job = next
          if (finished) companion.readStatus()
        }
      } catch (e) { }
      companion.clock = Date.now()
    }
  }

  Timer {
    id: statusPoll
    interval: 1000
    repeat: true
    running: companion.actionsEnabled && (companion.statusKey === "working" || companion.statusKey === "failed")
    onTriggered: { jobFile.reload(); companion.clock = Date.now() }
  }

  Component.onCompleted: {
    NotchMenuBridge.target = menuApi
    if (actionsEnabled) { jobFile.reload(); readStatus() }
  }
  Component.onDestruction: if (NotchMenuBridge.target === menuApi) NotchMenuBridge.target = null
}
