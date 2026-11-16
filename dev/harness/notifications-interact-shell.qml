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
//   notifytest popup <key>                a card on Omarchy's screen (newest first)
//   notifytest calls                      JSON list of "activate <key>" / "close <key> <reason>"
ShellRoot {
  id: harness
  property var notchConfig: JSON.parse(Quickshell.env("NOTCH_HARNESS_CONFIG") || "{}")
  property var calls: []

  ListModel { id: rows }

  QtObject {
    id: fakeService
    // The three calls Omarchy 4.5's service has that the notch uses.
    function rowIndexFor(key) {
      for (var i = 0; i < rows.count; i++) if (rows.get(i).key === key) return i
      return -1
    }
    function activate(key, instant) { harness.calls = harness.calls.concat(["activate " + key]) }
    function closeToast(key, reason, instant) { harness.calls = harness.calls.concat(["close " + key + " " + reason]) }
  }

  QtObject {
    id: fakeFacade
    property var stockItem: fakeService
    readonly property int apiVersion: 1
    readonly property string version: "2.0.0"
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
    function popup(key: string): string {
      rows.insert(0, { key: key })
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
