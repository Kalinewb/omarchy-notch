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
// Needs Omarchy 4.5 or newer: its service keeps the cards on screen in a
// ListModel of rows (key, ts, ...) and draws them in one PanelWindow per
// screen. Both are found by shape among the service's children, not by name,
// and anything not found leaves Omarchy's toast alone.
//
// The one thing it changes is whether those windows are visible. While the
// notch is taking toasts the windows are off, and they come on only for a row
// the notch will not draw. So Omarchy's toast is back the moment:
//
//   - no notch is running, or it is a notch that doesn't speak this bridge
//   - the notch says it isn't taking them (setting off, notifications off,
//     bar hidden -- NotificationsCompanion.qml's `takeOver`)
//   - a row is older than the notch's notification source (a toast restored
//     after a restart, or a history replay the user asked for), is not in
//     Omarchy's live.json at all (a card that asked not to be kept, "No recent
//     notifications"), or holds a code, which the notch leaves to Omarchy
//   - a row the notch hasn't drawn: waiting for a free line in a burst,
//     unreadable or declined (the notch's `shows`)
//
// A new row is not in live.json for a moment (Omarchy writes it a quarter of a
// second after the card arrives), so a row of the kind the file keeps is given
// a short grace to be drawn before its toast is let through.
Item {
  id: root
  visible: false

  // Injected by the host after this is created.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property int apiVersion: 2
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

  // --- what Omarchy has on screen ----------------------------------------------

  // Omarchy's list of cards, and its Variants of windows, found among the
  // service's children.
  property var toastModel: null
  property var variants: null
  // Omarchy's NotificationServer, found by its model of tracked notifications.
  property var stockServer: null
  property int windowsBound: 0
  // Bumped when a row changes without the count moving (a card updated in place).
  property int revision: 0
  // Bumped while a row is still waiting to be drawn, so the decision is made again.
  property int tick: 0

  // How long a new row may wait for the notch to draw it before Omarchy's toast
  // is let through: the file is written 250 ms after the card arrives.
  readonly property int graceMs: 900

  readonly property int toastCount: toastModel ? toastModel.count : 0

  // Whether the notch can say which toasts it has drawn.
  readonly property bool suppressing: takeOver && !!toastModel && typeof notch.shows === "function"

  // A row the notch will draw once the file has it: one of the kind the file
  // keeps, written a moment ago.
  function pending(row, now) {
    if (!row || row.restored === true || row.transient === true) return false
    if (String(row.key || "").indexOf("placeholder") === 0) return false
    if (String(row.code || "") !== "" || String(row.codes || "") !== "") return false
    var ts = Number(row.ts)
    return ts > 0 && now - ts * 1000 < graceMs
  }

  // Whether some row is within its grace, so the clock below keeps running.
  function waiting(ticked) {
    if (!suppressing) return false
    var now = Date.now()
    for (var i = 0; i < toastCount; i++) {
      var row = toastModel.get(i)
      if (pending(row, now) && notch.shows(row.key, row.ts) !== true) return true
    }
    return false
  }

  Timer {
    interval: 100
    repeat: true
    running: root.waiting(root.tick + root.revision)
    onTriggered: root.tick++
  }

  // Whether Omarchy's toast is off screen right now. Reads the model's count
  // and rows so it is re-asked whenever a toast arrives, changes or leaves, and
  // the notch's `shows` so it is re-asked when the notch draws one. A notch that
  // can't say which toasts it has drawn hides none.
  readonly property bool hideToasts: {
    tick; revision
    if (!suppressing) return false
    var now = Date.now()
    for (var i = 0; i < toastCount; i++) {
      var row = toastModel.get(i)
      if (!row || !row.key || !(Number(row.ts) > 0)) return false
      if (notch.shows(row.key, row.ts) === true) continue
      if (!pending(row, now)) return false
    }
    return true
  }

  Connections {
    target: root.toastModel
    ignoreUnknownSignals: true
    function onDataChanged() { root.revision++ }
    function onModelReset() { root.revision++ }
  }

  // --- the popup windows -------------------------------------------------------

  function attach() {
    toastModel = null
    variants = null
    stockServer = null
    var svc = stock.item
    if (!svc) return
    var data = svc.data
    var models = []
    for (var i = 0; i < data.length; i++) {
      var o = data[i]
      if (!o) continue
      if (o.trackedNotifications !== undefined) stockServer = o
      else if (o.instances !== undefined && o.model !== undefined && !variants) variants = o
      else if (typeof o.count === "number" && typeof o.get === "function" && typeof o.insert === "function"
               && typeof o.remove === "function") models.push(o)
    }
    // Only a list that cannot be mistaken for another is used.
    if (models.length === 1) toastModel = models[0]
    if (!variants) console.warn("kalinewb.notch-notifications: no popup window found in Omarchy's service; its toast will show as usual")
    if (!toastModel) console.warn("kalinewb.notch-notifications: no list of toasts found in Omarchy's service; its toast will show as usual")
    bindWindows()
  }

  // The server, where a plugin that counts notifications looks for it. Omarchy's
  // own service has the NotificationServer among its children, and a plugin that
  // reaches it through `firstPartyServiceFor("omarchy.notifications")` takes the
  // child that has `trackedNotifications` (Arc Dock's counter does). Here that
  // service is inside the Loader above, one level down, so this is the same
  // thing at the level they look: the model and the signal, passed on.
  QtObject {
    id: serverMirror
    readonly property var trackedNotifications: root.stockServer ? root.stockServer.trackedNotifications : undefined
    signal notification(var notification)
  }
  Connections {
    target: root.stockServer
    ignoreUnknownSignals: true
    function onNotification(notification) { serverMirror.notification(notification) }
  }

  // The window's own test (Omarchy's), and ours on top of it.
  function windowOn(w) {
    var stockOn = w.stepAside !== true || w.hasSomethingToShow === true
    if (!suppressing) return stockOn
    // While the notch is taking toasts the windows are off, idle as well: they
    // are mapped only to show a toast the notch won't.
    return toastCount > 0 && !hideToasts && stockOn
  }

  // One function per window, so each binding keeps its own.
  function bindOne(w) {
    w.visible = Qt.binding(function () { return root.windowOn(w) })
  }

  function bindWindows() {
    var bound = 0
    if (variants && toastModel && stock.item) {
      var list = variants.instances || []
      for (var i = 0; i < list.length; i++) {
        var w = list[i]
        if (!w || w.visible === undefined) continue
        bindOne(w)
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
