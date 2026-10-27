import QtQuick
import Quickshell
import Quickshell.Io
import "notch" as Notch
import "notch/bridge"

// dev/harness/shell.qml, plus a stand-in for the notifications companion's
// loaded service (what Omarchy's real Service.qml exposes through it), so
// dev/notifications-interact.sh can see which calls a click makes:
//
//   notifytest facade <true|false>        the companion is loaded / is not
//   notifytest popup <originalId> <ts>    a row on Omarchy's popup list (newest first)
//   notifytest calls                      JSON list of "invoke <i>" / "dismiss <i>"
ShellRoot {
  id: harness
  property var notchConfig: JSON.parse(Quickshell.env("NOTCH_HARNESS_CONFIG") || "{}")
  property var calls: []

  ListModel { id: rows }

  QtObject {
    id: fakeService
    property var popupModel: rows
    function invokePopupDefault(index) { harness.calls = harness.calls.concat(["invoke " + index]) }
    function dismissPopup(index) { harness.calls = harness.calls.concat(["dismiss " + index]) }
  }

  QtObject {
    id: fakeFacade
    property var stockItem: fakeService
    readonly property int apiVersion: 1
    readonly property string version: "1.0.0"
  }

  IpcHandler {
    target: "harness"
    function setNotch(json: string): string {
      try { harness.notchConfig = JSON.parse(json) } catch (e) { return "bad-json" }
      return "ok"
    }
  }

  IpcHandler {
    target: "notifytest"
    function facade(on: string): string { NotchNotificationsBridge.facade = on === "true" ? fakeFacade : null; return on }
    function popup(originalId: string, timestamp: string): string {
      rows.insert(0, { originalId: Number(originalId), timestamp: Number(timestamp) })
      return String(rows.count)
    }
    function calls(): string { return JSON.stringify(harness.calls) }
  }

  Notch.Bar {
    barConfig: ({
      position: "top",
      transparent: false,
      layout: { left: [], center: [], right: [] },
      notch: harness.notchConfig
    })
  }
}
