import QtQuick
import Quickshell
import Quickshell.Io

// Everything about one companion: the small plugin that lets the notch be one
// of Omarchy's own surfaces. Bar.qml has three of these, one per companion:
//
//   kalinewb.notch-menu           clonedFrom omarchy.menu: every menu call
//                                 (SUPER + SPACE, `omarchy menu`, the bar's menu
//                                 button, every picker) opens in the notch
//   kalinewb.notch-osd            clonedFrom omarchy.osd: volume, brightness and
//                                 media show in the notch
//   kalinewb.notch-notifications  clonedFrom omarchy.notifications: Omarchy's own
//                                 service runs unchanged, and its toast stays off
//                                 screen while the notch shows the same one
//
// Omarchy routes the source's calls to whichever enabled plugin says
// `clonedFrom: <source>`. Each companion lives in companion/<id> and is copied
// once into ~/.config/omarchy/plugins; its go-between asks the notch first,
// through its own bridge singleton (bridge/), and falls back to Omarchy's own
// surface when the notch declines, so nothing is ever dropped.
//
// This file owns:
//   - the bridge registration: `api`, the only object the companion can reach
//     the notch through (each instance's api is set in Bar.qml)
//   - the companion folder's state, and the jobs that install or update it
//
// The jobs change the plugins folder, which reloads every plugin and destroys
// this notch, so they run detached (Detached.qml) and report through a status
// file outside that folder, exactly as bin/notch-update does.
Item {
  id: companion
  visible: false

  // The notch's Bar.qml root.
  property var bar: null
  // Which companion: its plugin id, the Omarchy id it stands in for, the word
  // for it in a sentence ("the menu companion"), its unit name and status file.
  property string companionId: ""
  property string sourceId: ""
  property string label: ""
  property string unitPrefix: ""
  property string statusName: ""
  // The notch setting that asks for it.
  property bool wanted: false
  // Its bridge singleton, and what it may reach there.
  //
  // Not the Bar root: anything that loads bridge/Connector.qml can read the
  // bridge's target, and the root carries the notch's shell facade, its
  // settings writer and its updater. `api` only carries what that companion
  // needs to ask.
  property var bridge: null
  property QtObject api: null

  // The notch's own copy of the companion.
  readonly property string version: "1.0.0"
  readonly property bool bridged: !!bridge && bridge.target === api
  readonly property var facade: bridge ? bridge.facade : null
  readonly property string facadeRoute: facade ? String(facade.route || "") : ""

  // Only a hosted notch installs or updates anything; a test notch reports and
  // does nothing (NOTCH_FORCE_COMPANION=1 lets a suite opt in).
  readonly property bool actionsEnabled: !!bar && ((!!bar.shell && !bar.harnessed) || Quickshell.env("NOTCH_FORCE_COMPANION") === "1")

  readonly property string script: String(Qt.resolvedUrl("bin/notch-companion")).replace(/^file:\/\//, "")
  readonly property string statusPath: (Quickshell.env("NOTCH_COMPANION_STATE_DIR")
    || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/kalinewb.notch")) + "/" + statusName

  // One script, three companions: which one is in the environment, so `status`
  // and every job read the same folder the notch is asking about.
  readonly property var idEnv: ["env", "NOTCH_COMPANION_ID=" + companionId, "NOTCH_COMPANION_SOURCE_ID=" + sourceId,
                                "NOTCH_COMPANION_LABEL=" + label]

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
  // loaded: Omarchy creates a menu or panel plugin's entry point when it is
  // first called and may drop it afterwards, so "has it registered with the
  // bridge" says "absent" for a perfectly good companion most of the time. A
  // live facade is still worth having -- it is the only thing that can report
  // the running API and version -- so it is used when it is there.
  readonly property string companionState: {
    var info = installed || {}
    if (facade) {
      var sameApi = Number(facade.apiVersion) === Number(bridge.apiVersion)
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
    if (wanted && bar && bar.barHidden) return "hidden-bar"
    return wanted ? "active-on" : "active-off"
  }

  function dismiss() { dismissedAt = Date.now(); clock = Date.now() }

  // The switch is the whole of the user's part. Whatever the companion folder
  // needs to match it -- installing, enabling, bringing up to date -- the notch
  // does by itself, once per state it finds: a job that failed is not retried
  // until the switch changes or the notch restarts, and Setup reports it.
  property string keptInStep: ""
  property real keptInStepAt: 0
  function keepInStep() {
    if (!actionsEnabled || !wanted) { keptInStep = ""; keptInStepAt = 0; return }
    var state = companionState
    if (state !== "absent" && state !== "disabled" && state !== "outdated") return
    if (statusKey === "working" || keptInStep === state) return
    // An install copies the folder and then enables it, so the state moves
    // absent -> disabled while the job is still running: without this, that
    // second state launched a second job to find there was nothing to do.
    if (keptInStepAt > 0 && Date.now() - keptInStepAt < 30000) return
    keptInStep = state
    keptInStepAt = Date.now()
    startJob(state === "outdated" ? "sync" : "install")
  }
  onInstalledChanged: keepInStep()
  // Switching it off and on again is how you ask for another try.
  onWantedChanged: {
    keptInStep = ""
    keptInStepAt = 0
    keepInStep()
  }

  function setUp() { return startJob("install") }
  function update() { return startJob("sync") }
  function remove() { return startJob("remove") }

  Detached { id: detached }

  function startJob(verb) {
    if (!actionsEnabled || statusKey === "working") return false
    detached.launch(unitPrefix, idEnv.concat([script, verb, statusPath]),
                    ["NOTCH_COMPANION_DIR", "NOTCH_COMPANION_SOURCE", "NOTCH_COMPANION_LIST", "NOTCH_COMPANION_ENABLE",
                     "NOTCH_COMPANION_REMOVE", "NOTCH_COMPANION_VALIDATE", "NOTCH_COMPANION_SESSION_LOCKED",
                     "NOTCH_COMPANION_STATE_DIR"], "NOTCH_UPDATE_DETACH")
    job = { phase: "working", verb: verb, startedAt: Date.now(), finishedAt: 0, message: "", launched: true }
    clock = Date.now()
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
    if (bridge) bridge.target = api
    if (actionsEnabled) { jobFile.reload(); readStatus() }
  }
  Component.onDestruction: if (bridge && bridge.target === api) bridge.target = null
}
