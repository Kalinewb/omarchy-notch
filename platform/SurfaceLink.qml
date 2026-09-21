import QtQuick
import Quickshell
import Quickshell.Io

// Talk to the notch from outside it. **Copy this file into your plugin** --
// don't import it from the notch's folder, or your plugin breaks whenever the
// notch isn't installed.
//
// A bar widget doesn't need this: it is given a `surfaceHost` directly. This is
// for the parts of a plugin that run where no host is handed out -- a service,
// a panel loaded by another kind, a CLI helper.
//
// It answers two questions:
//   present   is a notch running, and is it the bar?
//   accepted  did it accept *your* integration?
// and offers claim()/release() for the resting-notch line.
//
// Both answers arrive through a file the notch writes and through
// `omarchy-shell`, which any process running as this user could also write or
// stand in for. So:
//
//   **A surface that exists to warn the user -- an authentication prompt, an
//   identity check, a camera-in-use cue -- must keep its own UI no matter what
//   this says.** Use it to mirror into the notch, never to hide the warning.
//   Standing your own UI down is only safe on an in-process `surfaceHost` answer.
//
// Usage:
//
//   SurfaceLink {
//     id: notch
//     pluginId: "acme.demo"
//     shell: root.shell            // optional: a fast "is the notch the bar" test
//   }
//   ...
//   notch.claim({ title: "Switching to test…", priority: "persistent", ttlMs: 30000 },
//               function (result) { if (result !== "shown") showMyOwnCue() })
QtObject {
  id: link

  required property string pluginId
  // Your plugin's `shell`, if you have it. When the active bar isn't the notch
  // there is nothing to ask, and this skips the file and the process entirely.
  property var shell: null
  property string statePath: (Quickshell.env("NOTCH_PLATFORM_STATE_DIR")
    || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/kalinewb.notch")) + "/platform.json"
  property var shellCommand: ["omarchy-shell"]
  property int ackTimeoutMs: 250
  // The contract version your integration was written for.
  property int wantContract: 1

  readonly property bool barIsNotch: {
    if (!shell || !shell.barConfig) return true   // can't tell: ask anyway
    return String(shell.barConfig.id || "") === "kalinewb.notch"
  }

  property var state: ({})
  readonly property real beatAt: Number(state.beatAt || 0)
  readonly property real staleAfterMs: Number(state.staleAfterMs || 6000)
  property real clock: Date.now()

  // The notch is there when it says so and has said so recently. A crash runs
  // no destruction handler, so staleness is the backstop.
  readonly property bool present: barIsNotch && state.present === true
    && Number(state.contract || 0) >= wantContract
    && (clock - beatAt) < staleAfterMs

  readonly property bool accepted: present && !!state.accepted && state.accepted[pluginId] !== undefined
  readonly property int contract: Number(state.contract || 0)
  readonly property string generation: String(state.generation || "")

  property string lastGeneration: ""
  // key -> the last activity claimed under it, so a rebuilt notch can be told
  // again without the plugin having to notice.
  property var held: ({})

  onGenerationChanged: {
    if (generation === "" || generation === lastGeneration) return
    var previous = lastGeneration
    lastGeneration = generation
    if (previous === "") return
    for (var key in held) link.claim(held[key], null)
  }

  readonly property var beatFile: FileView {
    path: link.statePath
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try { link.state = JSON.parse(text()) } catch (e) { link.state = ({}) }
      link.clock = Date.now()
    }
    onLoadFailed: link.state = ({})
  }

  // Directory watches can go quiet, so the file is re-read on a slow tick too.
  readonly property var poll: Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: { link.clock = Date.now(); link.beatFile.reload() }
  }

  // --- asking the notch ------------------------------------------------------

  property var pending: []
  property var inFlight: null

  // claim(activity, callback): callback gets "shown", "queued",
  // "declined:<reason>", "timeout" or "absent". Only "shown" means it is on
  // screen, and even then, see the warning at the top of this file.
  function claim(activity, callback) {
    if (!present || !accepted) { if (callback) callback("absent"); return "absent" }
    var key = activity && activity.key ? String(activity.key) : pluginId
    var kept = JSON.parse(JSON.stringify(held))
    kept[key] = activity
    held = kept
    send(["notch", "claim", pluginId, JSON.stringify(activity)], callback)
    return "sent"
  }

  function release(key) {
    var name = String(key || pluginId)
    var kept = JSON.parse(JSON.stringify(held))
    delete kept[name]
    held = kept
    if (!present) return "absent"
    send(["notch", "release", pluginId, name], null)
    return "sent"
  }

  // One call at a time, with at most one waiting: a burst of claims shouldn't
  // start a burst of processes.
  function send(argv, callback) {
    var job = { argv: argv, callback: callback }
    if (inFlight) { pending = [job]; return }
    run(job)
  }

  function run(job) {
    inFlight = job
    callProcess.command = shellCommand.concat(job.argv)
    callProcess.running = true
    timeout.restart()
  }

  readonly property var callProcess: Process {
    stdout: StdioCollector {
      onStreamFinished: {
        var answer = String(text).trim()
        link.finish(answer === "" ? "absent" : answer)
      }
    }
    onRunningChanged: if (!running && link.inFlight) link.finish("absent")
  }

  readonly property var timeout: Timer {
    interval: link.ackTimeoutMs
    onTriggered: if (link.inFlight) link.finish("timeout")
  }

  function finish(result) {
    var job = inFlight
    inFlight = null
    timeout.stop()
    if (job && job.callback) job.callback(result)
    if (pending.length > 0) {
      var next = pending[0]
      pending = []
      run(next)
    }
  }
}
