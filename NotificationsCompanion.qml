import QtQuick
import Quickshell
import Quickshell.Io
import "bridge"

// Everything about the notifications companion, the small plugin that keeps
// Omarchy's own toast off screen while the notch shows the same notification
// (see README, "Suppress Omarchy's own toast").
//
// Omarchy loads whichever enabled plugin says `clonedFrom:
// omarchy.notifications` instead of its own. That plugin is
// companion/kalinewb.notch-notifications, installed once into
// ~/.config/omarchy/plugins. It runs Omarchy's real Service.qml, unchanged,
// from $OMARCHY_PATH, and only decides whether that service's popup window is
// visible -- by asking this object, through the bridge, whether the notch is
// taking the toasts right now.
//
// The OSD companion's arrangement (OsdCompanion.qml), with its own bridge
// singleton so no companion can reach another's API.
Item {
  id: companion
  visible: false

  // The notch's Bar.qml root.
  property var bar: null

  // --- what the companion may ask the notch ----------------------------------
  //
  // Not the Bar root. Whether the notch is taking Omarchy's toasts right now,
  // and the time its notification source started (anything older, the notch
  // never shows, so the companion leaves those on Omarchy's own toast).
  readonly property QtObject notificationsApi: QtObject {
    readonly property bool takeOver: !!companion.bar && companion.bar.notchSuppressNativeToast
      && !companion.bar.barHidden && !!companion.bar.notificationsSource
      && companion.bar.notificationsSource.enabled
    readonly property real since: companion.bar && companion.bar.notificationsSource
      ? companion.bar.notificationsSource.startedAt : 0
  }

  readonly property string id: "kalinewb.notch-notifications"
  readonly property string version: "1.0.0"
  readonly property bool bridged: NotchNotificationsBridge.target === notificationsApi
  // What the running companion found: Omarchy's service loaded, and a popup
  // window it can keep off screen.
  readonly property string stockError: NotchNotificationsBridge.facade ? String(NotchNotificationsBridge.facade.stockError || "") : ""
  readonly property bool suppressible: !!NotchNotificationsBridge.facade && NotchNotificationsBridge.facade.suppressible === true
  readonly property bool hiding: !!NotchNotificationsBridge.facade && NotchNotificationsBridge.facade.hideToasts === true

  // Only a hosted notch installs or updates anything; a test notch reports and
  // does nothing (NOTCH_FORCE_COMPANION=1 lets a suite opt in).
  readonly property bool actionsEnabled: !!bar && ((!!bar.shell && !bar.harnessed) || Quickshell.env("NOTCH_FORCE_COMPANION") === "1")

  readonly property string script: String(Qt.resolvedUrl("bin/notch-companion")).replace(/^file:\/\//, "")
  readonly property string statusPath: (Quickshell.env("NOTCH_COMPANION_STATE_DIR")
    || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/kalinewb.notch")) + "/companion-notifications.json"

  // One script, three companions: which one is in the environment, so `status`
  // and every job read the same folder the notch is asking about.
  readonly property var idEnv: ["env", "NOTCH_COMPANION_ID=" + id, "NOTCH_COMPANION_SOURCE_ID=omarchy.notifications"]

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
  // it only exists once the shell has loaded the companion, so its absence
  // says nothing about the folder.
  readonly property string companionState: {
    var facade = NotchNotificationsBridge.facade
    var info = installed || {}
    if (facade) {
      var sameApi = Number(facade.apiVersion) === NotchNotificationsBridge.apiVersion
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
    if (bar && bar.notchSuppressNativeToast && bar.barHidden) return "hidden-bar"
    return bar && bar.notchSuppressNativeToast ? "active-on" : "active-off"
  }

  function dismiss() { dismissedAt = Date.now(); clock = Date.now() }

  // The switch is the whole of the user's part: whatever the companion folder
  // needs to match it, the notch does by itself, once per state it finds.
  property string keptInStep: ""
  property real keptInStepAt: 0
  function keepInStep() {
    if (!actionsEnabled || !bar || !bar.notchSuppressNativeToast) { keptInStep = ""; keptInStepAt = 0; return }
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
    function onNotchSuppressNativeToastChanged() {
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
      argv = ["systemd-run", "--user", "--collect", "--quiet", "--unit", "kalinewb-notch-notifications-companion-" + Date.now()]
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
    NotchNotificationsBridge.target = notificationsApi
    if (actionsEnabled) { jobFile.reload(); readStatus() }
  }
  Component.onDestruction: if (NotchNotificationsBridge.target === notificationsApi) NotchNotificationsBridge.target = null
}
