import QtQuick
import Quickshell

// Omarchy's notification service, with its toast kept off screen while the
// notch is showing the same thing.
//
// This plugin says `clonedFrom: omarchy.notifications`, so enabling it turns
// Omarchy's own off and loads this in its place. It does not replace the
// service: it loads Omarchy's real Service.qml from $OMARCHY_PATH by URL, so
// the notification server, DND, history, the files the notch reads and the
// `notifications` IPC target (dismissOne, invokeLast, showHistory, ...) are
// all Omarchy's own code, following Omarchy as it updates. Nothing on disk is
// patched -- which is what makes this work on a packaged install, where
// $OMARCHY_PATH belongs to root.
//
// The one thing it changes is whether the popup window is visible. Omarchy
// draws toasts in one PanelWindow per screen, bound to
// `popupModel.count > 0`; that binding is replaced here with the same test
// and one more: the toasts stay off screen only while every row on it is one
// the notch will show. So Omarchy's toast is back the moment:
//
//   - no notch is running, or it is a notch that doesn't speak this bridge
//   - the notch says it isn't taking them (setting off, notifications off,
//     bar hidden -- NotificationsCompanion.qml's `takeOver`)
//   - a row is older than the notch's notification source (a toast restored
//     after a restart, or a history replay the user asked for), or isn't a
//     notification at all ("No recent notifications")
//
// If Omarchy restructures the file so there is no popup window to find, the
// toasts simply show: the fallback is always Omarchy's own behaviour.
Item {
  id: root
  visible: false

  // Injected by the host after this is created.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property int apiVersion: 1
  readonly property string version: manifest && manifest.version ? String(manifest.version) : ""
  property string stockError: ""

  // From the environment only, never from the injected omarchyPath: a source
  // that changed after creation would reload the service, and with it the
  // notification server, mid-session.
  readonly property string stockUrl: Quickshell.env("NOTCH_NOTIFICATIONS_STOCK_URL")
    || ("file://" + (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/shell/plugins/notifications/Service.qml")

  Loader {
    id: stock
    asynchronous: false
    source: root.stockUrl
    onLoaded: {
      root.stockError = ""
      if ("shell" in item) item.shell = Qt.binding(function () { return root.shell })
      root.attach()
    }
    onStatusChanged: {
      if (status === Loader.Error) {
        root.stockError = "couldn't load " + root.stockUrl
        console.warn("kalinewb.notch-notifications: " + root.stockError)
      }
    }
  }
  readonly property var stockItem: stock.item

  // The notch's bridge. A missing notch folder is a Loader error and nothing else.
  Loader {
    id: link
    asynchronous: false
    source: Quickshell.env("NOTCH_NOTIFICATIONS_CONNECTOR_URL") || Qt.resolvedUrl("../kalinewb.notch/bridge/Connector.qml")
  }
  readonly property var bridge: link.item && link.item.notificationsBridge ? link.item.notificationsBridge : null
  readonly property var notch: bridge && Number(bridge.apiVersion) === apiVersion && bridge.target ? bridge.target : null
  readonly property bool takeOver: !!notch && notch.takeOver === true

  // Whether Omarchy's toast is off screen right now. Reads popupModel.count so
  // it is re-asked whenever a toast arrives or leaves.
  readonly property bool hideToasts: {
    if (!takeOver || !stockItem || !stockItem.popupModel) return false
    var model = stockItem.popupModel
    var since = Number(notch.since || 0)
    if (since <= 0) return false
    for (var i = 0; i < model.count; i++) {
      var row = model.get(i)
      if (!row || Number(row.originalId) < 0 || Number(row.timestamp) < since) return false
    }
    return true
  }

  // --- the popup window -------------------------------------------------------

  // Omarchy's Variants of popup windows, found among the service's children.
  property var variants: null
  property int windowsBound: 0

  function attach() {
    variants = null
    var svc = stock.item
    if (!svc) return
    var data = svc.data
    for (var i = 0; i < data.length; i++) {
      var o = data[i]
      if (o && o.instances !== undefined && o.model !== undefined) { variants = o; break }
    }
    if (!variants) console.warn("kalinewb.notch-notifications: no popup window found in Omarchy's service; its toast will show as usual")
    bindWindows()
  }

  function bindWindows() {
    var bound = 0
    if (variants && stock.item) {
      var list = variants.instances || []
      for (var i = 0; i < list.length; i++) {
        var w = list[i]
        if (!w || w.visible === undefined) continue
        w.visible = Qt.binding(function () {
          return !!root.stockItem && root.stockItem.popupModel.count > 0 && !root.hideToasts
        })
        bound++
      }
    }
    windowsBound = bound
  }

  // A screen plugged in later gets its own window; bind that one too.
  Connections {
    target: root.variants
    ignoreUnknownSignals: true
    function onInstancesChanged() { root.bindWindows() }
  }
  Connections {
    target: Quickshell
    function onScreensChanged() { Qt.callLater(root.bindWindows) }
  }

  // What the notch's report reads.
  readonly property bool suppressible: windowsBound > 0

  Component.onCompleted: if (bridge) bridge.facade = root
  Component.onDestruction: if (bridge && bridge.facade === root) bridge.facade = null
}
