import QtQuick
import Quickshell
import Quickshell.Io
import "notch" as Notch

// The real Bar.qml with a fake host that keeps the shell config in memory, so
// the settings panel's writes land somewhere a check can read, and the bar
// reloads from them the way it does in a session. Used by dev/settings.sh.
//
//   quickshell ipc -p <dir> call settingstest config          bar.notch as JSON
//   quickshell ipc -p <dir> call settingstest writes          how many writes it took
//   quickshell ipc -p <dir> call settingstest many <json>     setNotchSettings(<json>)
ShellRoot {
  id: shellRoot

  property var config: ({
    bar: {
      position: "top",
      transparent: false,
      layout: { left: [], center: [], right: [] },
      notch: JSON.parse(Quickshell.env("NOTCH_HARNESS_CONFIG") || "{}")
    }
  })
  property int writes: 0

  QtObject {
    id: fakeShell
    // Same contract as Omarchy's: the function edits a copy, the copy is kept.
    function mutateShellConfig(mutator) {
      var next = JSON.parse(JSON.stringify(shellRoot.config))
      mutator(next)
      shellRoot.config = next
      shellRoot.writes++
      return true
    }
    function firstPartyServiceFor(id) { return null }
    function pluginShellForBarEntry(ownerId, moduleName) { return null }
  }

  IpcHandler {
    target: "settingstest"
    function config(): string { return JSON.stringify(shellRoot.config.bar.notch) }
    function writes(): string { return String(shellRoot.writes) }
    function many(json: string): string {
      var values
      try { values = JSON.parse(json) } catch (e) { return "bad-json" }
      return notch.setNotchSettings(values) ? "ok" : "unsaved"
    }
  }

  Notch.Bar {
    id: notch
    shell: fakeShell
    barConfig: shellRoot.config.bar
  }
}
