import QtQuick
import Quickshell
import Quickshell.Io
import "bridge"

// Everything about the OSD companion, the small plugin that lets the notch be
// Omarchy's on-screen display (see README, "Show the OSD in the notch").
//
// Omarchy sends every OSD call -- the volume and brightness keys, the media
// buttons, anything calling `summon("omarchy.osd", …)` -- to whichever enabled
// plugin says `clonedFrom: omarchy.osd`. That plugin is
// companion/kalinewb.notch-osd, installed once into ~/.config/omarchy/plugins.
// Its go-between asks the notch to take the call; when the notch declines (the
// setting is off, a panel is open, the bar is hidden, no notch is running) it
// shows Omarchy's own card instead, so a key press never does nothing.
//
// This is the menu companion's arrangement, with one companion's worth of
// difference: `bin/notch-companion` does the installing for both, told which
// one by NOTCH_COMPANION_ID, and each has its own bridge singleton so neither
// companion can reach the other's API.
Item {
  id: companion
  visible: false

  // The notch's Bar.qml root.
  property var bar: null

  // --- what the companion may do to the notch ----------------------------------
  //
  // Not the Bar root: anything that loads bridge/Connector.qml can read
  // NotchOsdBridge.target, and the root carries the notch's shell facade, its
  // settings writer and its updater. This object can show an OSD, hide one,
  // and answer whether the notch wants them.
  readonly property QtObject osdApi: QtObject {
    // Omarchy's payload, straight through. Answers "shown" or
    // "declined:<reason>"; the companion falls back on anything but "shown".
    function showOsd(payloadJson) {
      return companion.bar ? String(companion.bar.showOsd(payloadJson)) : "declined:no-notch"
    }
    function hideOsd() { if (companion.bar) companion.bar.hideOsd() }
    readonly property bool osdShown: !!companion.bar && companion.bar.osdShown
    readonly property bool notchReplaceOsd: !!companion.bar && companion.bar.notchReplaceOsd
    readonly property bool barHidden: !!companion.bar && companion.bar.barHidden
  }

  readonly property string id: "kalinewb.notch-osd"
  readonly property string version: "1.0.0"
  readonly property bool bridged: NotchOsdBridge.target === osdApi
  readonly property string facadeRoute: NotchOsdBridge.facade ? String(NotchOsdBridge.facade.route || "") : ""
  readonly property string facadeDeclined: NotchOsdBridge.facade ? String(NotchOsdBridge.facade.declined || "") : ""

  // Only a hosted notch installs or updates anything; a test notch reports and
  // does nothing (NOTCH_FORCE_COMPANION=1 lets a suite opt in).
  readonly property bool actionsEnabled: !!bar && ((!!bar.shell && !bar.harnessed) || Quickshell.env("NOTCH_FORCE_COMPANION") === "1")

  readonly property string script: String(Qt.resolvedUrl("bin/notch-companion")).replace(/^file:\/\//, "")
  readonly property string statusPath: (Quickshell.env("NOTCH_COMPANION_STATE_DIR")
    || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/kalinewb.notch")) + "/companion-osd.json"

  // One script, two companions: which one is in the environment, so `status`
  // and every job read the same folder the notch is asking about.
  readonly property var idEnv: ["env", "NOTCH_COMPANION_ID=" + id, "NOTCH_COMPANION_SOURCE_ID=omarchy.osd"]

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
  // What is on disk is the answer. A live facade is better when there is one --
  // it is the only thing that can report the running API and version -- but
  // Omarchy creates a panel plugin's entry point lazily, so its absence says
  // nothing about the folder.
  readonly property string companionState: {
    var facade = NotchOsdBridge.facade
    var info = installed || {}
    if (facade) {
      var sameApi = Number(facade.apiVersion) === NotchOsdBridge.apiVersion
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
    if (bar && bar.notchReplaceOsd && bar.barHidden) return "hidden-bar"
    return bar && bar.notchReplaceOsd ? "active-on" : "active-off"
  }

  function dismiss() { dismissedAt = Date.now(); clock = Date.now() }

  // The switch is the whole of the user's part: whatever the companion folder
  // needs to match it, the notch does by itself, once per state it finds.
  property string keptInStep: ""
  property real keptInStepAt: 0
  function keepInStep() {
    if (!actionsEnabled || !bar || !bar.notchReplaceOsd) { keptInStep = ""; keptInStepAt = 0; return }
    var state = companionState
    if (state !== "absent" && state !== "disabled" && state !== "outdated") return
    if (statusKey === "working" || keptInStep === state) return
    // An install copies the folder and then enables it, so the state moves
    // absent -> disabled while the job is still running.
    if (keptInStepAt > 0 && Date.now() - keptInStepAt < 30000) return
    keptInStep = state
    keptInStepAt = Date.now()
    startJob(state === "outdated" ? "sync" : "install")
  }
  onInstalledChanged: keepInStep()
  Connections {
    target: companion.bar
    // Switching it off and on again is how you ask for another try.
    function onNotchReplaceOsdChanged() {
      companion.keptInStep = ""
      companion.keptInStepAt = 0
      companion.keepInStep()
    }
  }

  function setUp() { return startJob("install") }
  function update() { return startJob("sync") }
  function remove() { return startJob("remove") }

  // Detached, in its own systemd user unit: the job reloads every plugin and
  // takes this notch down with it.
  function startJob(verb) {
    if (!actionsEnabled || statusKey === "working") return false
    var run = idEnv.concat([script, verb, statusPath])
    var argv
    if ((Quickshell.env("NOTCH_UPDATE_DETACH") || "systemd-run") === "systemd-run") {
      argv = ["systemd-run", "--user", "--collect", "--quiet", "--unit", "kalinewb-notch-osd-companion-" + Date.now()]
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
    command: companion.idEnv.concat([companion.script, "status"])
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
    NotchOsdBridge.target = osdApi
    if (actionsEnabled) { jobFile.reload(); readStatus() }
  }
  Component.onDestruction: if (NotchOsdBridge.target === osdApi) NotchOsdBridge.target = null
}
