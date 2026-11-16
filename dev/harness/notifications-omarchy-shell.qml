import QtQuick
import Quickshell
import Quickshell.Io
import "kalinewb.notch" as Notch
import "stock/Store.js" as Store

// The notch and the notifications companion, with Omarchy's own Service.qml
// (a copy of it with only the notification server taken out, so it cannot
// claim the real bus name) -- the real model, the real windows, the real
// live.json writer. dev/notifications-omarchy.sh drives it.
//
//   omarchytest info                         what the companion found, JSON
//   omarchytest arrive <key> <summary> <kind>  a card arrives the way the
//                                            service's own arrival path puts
//                                            one up: kind plain | transient
//   omarchytest close <key>                  Omarchy closes it (its own call)
//   omarchytest state                        the windows, the card count, live.json's readiness
ShellRoot {
  id: harness
  property var notchConfig: JSON.parse(Quickshell.env("NOTCH_HARNESS_CONFIG") || "{}")

  Loader {
    id: companion
    source: "kalinewb.notch-notifications/Service.qml"
  }
  readonly property var svc: companion.item ? companion.item.stockItem : null

  IpcHandler {
    target: "harness"
    function setNotch(json: string): string {
      try { harness.notchConfig = JSON.parse(json) } catch (e) { return "bad-json" }
      return "ok"
    }
  }

  IpcHandler {
    target: "omarchytest"
    function info(): string {
      var c = companion.item
      return JSON.stringify({ loaded: !!c, stock: !!harness.svc, apiVersion: c ? c.apiVersion : 0,
                              model: c ? c.toastModel !== null : false, bound: c ? c.windowsBound : 0,
                              suppressible: c ? c.suppressible : false, takeOver: c ? c.takeOver : false,
                              bridge: c ? !!c.bridge : false, notch: c ? !!c.notch : false })
    }
    function arrive(key: string, summary: string, kind: string): string {
      var s = harness.svc
      if (!s || !s.liveLoaded) return "not-ready"
      // Store.snapshot is what the service's arrival path makes a row with.
      var row = Store.snapshot({ id: 1, appName: "", summary: summary, body: "", hints: { transient: kind === "transient" },
                                 urgency: 1, expireTimeout: 0 }, key, { Normal: 1 })
      row.duration = 8000
      if (!s.reserveLive(key)) return "full"
      s.liveKeys[key].originalId = 1
      s.storePut(row)
      s.showRow(row)
      return "ok"
    }
    function close(key: string): string {
      if (!harness.svc) return "none"
      harness.svc.closeToast(key, "dismissed", true)
      return "ok"
    }
    function state(): string {
      var s = harness.svc
      var c = companion.item
      return JSON.stringify({ ready: !!s && s.liveLoaded === true, count: c && c.toastModel ? c.toastModel.count : -1,
                              mapped: s ? s.surfaceStates().map(function(x) { return x.mapped }) : [] })
    }
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
