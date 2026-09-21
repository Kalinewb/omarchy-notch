import QtQuick
import Quickshell

// The go-between for Omarchy's menu.
//
// This plugin says `clonedFrom: omarchy.menu`, so Omarchy sends every menu
// call here: SUPER + SPACE and the other menu keybinds, `omarchy menu`, the
// bar's menu button, the screen-recording indicator, and every
// omarchy-menu-select / -input picker. Each call is handed to whichever can
// serve it:
//
//   the notch   when a notch is running here, its "Replace the Omarchy menu"
//               setting is on, and it is in a state to show the menu
//   Omarchy's   otherwise -- loaded from $OMARCHY_PATH by URL, so it is the
//   own menu    real thing, not a copy, and it keeps following Omarchy
//
// It must never drop a request: a picker's caller waits on a done file with no
// timeout, so a request this can't serve is released instead (the script then
// exits rather than hanging).
//
// It reaches the notch through the notch's own bridge singleton, loaded by
// URL from the notch's folder; a missing or mismatched notch just means
// Omarchy's menu.
Item {
  id: root
  visible: false

  // Injected by the host after this is created, so everything below is a
  // binding, never a copy taken at creation.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property int apiVersion: 1
  readonly property string version: manifest && manifest.version ? String(manifest.version) : ""
  // "notch" or "stock": who took the last open, for the notch's report.
  property string route: ""
  // "shell" or "own": where Omarchy's own menu gets its app list from.
  property string appsSource: "shell"
  property string stockError: ""
  property string stockFirstSource: ""

  // Omarchy's own menu. Its window only exists while it is open, so loading it
  // costs nothing until it is used.
  Loader {
    id: stock
    asynchronous: false
    source: Quickshell.env("NOTCH_MENU_STOCK_URL") || ("file://" + root.omarchyPath + "/shell/plugins/menu/Menu.qml")
    onStatusChanged: {
      if (status === Loader.Error) root.stockError = String(sourceComponent ? sourceComponent.errorString() : "could not load Omarchy's menu")
      else if (status === Loader.Ready) root.stockError = ""
    }
  }
  Binding {
    target: stock.item
    property: "shell"
    when: stock.status === Loader.Ready
    value: root.appsSource === "own" ? appsProxy : root.shell
  }
  Binding {
    target: stock.item
    property: "omarchyPath"
    when: stock.status === Loader.Ready
    value: root.omarchyPath
  }

  // The notch's bridge. A missing notch folder is a Loader error and nothing else.
  Loader {
    id: link
    asynchronous: false
    source: Quickshell.env("NOTCH_MENU_CONNECTOR_URL") || Qt.resolvedUrl("../kalinewb.notch/bridge/Connector.qml")
  }
  // Omarchy's own menu, once loaded (the notch's checks read it).
  readonly property var stockItem: stock.item
  readonly property var bridge: link.item ? link.item.bridge : null
  readonly property int expectedApi: Number(Quickshell.env("NOTCH_MENU_BRIDGE_API") || apiVersion)
  readonly property var notch: {
    if (!bridge || Number(bridge.apiVersion) !== expectedApi) return null
    var target = bridge.target
    return target && typeof target.openMenuPayload === "function" ? target : null
  }

  // What the shell's toggle reads. The notch's menu counts only while it is
  // the Omarchy menu: with the setting off, a menu the notch opened by its own
  // gesture or keybind must not swallow SUPER + SPACE.
  readonly property bool opened: (notch && notch.notchReplaceMenu && notch.anyMenuOpen)
    || (stock.item ? stock.item.opened === true : false)

  // Omarchy's plugin lifecycle.
  function open(payloadJson) {
    if (root.notch && root.notch.openMenuPayload(payloadJson) === true) {
      root.releaseStock()
      root.route = "notch"
      return
    }
    if (stock.item) {
      // One action, one UI: a notch menu opened another way must not stay open
      // under Omarchy's own menu, which takes the keyboard outright.
      if (root.notch) root.notch.closeMenus()
      root.useOwnAppsIfEmpty(payloadJson)
      root.releaseStock()
      stock.item.open(payloadJson)
      root.route = "stock"
      return
    }
    // Nothing can serve it: let a waiting picker go rather than hang it.
    root.releasePayload(payloadJson)
    console.warn("kalinewb.notch-menu: no menu to open" + (root.stockError ? " (" + root.stockError + ")" : ""))
  }

  function close() {
    if (root.notch) root.notch.closeMenus()
    if (stock.item) stock.item.close()
  }

  function refresh() {
    if (root.notch) root.notch.refreshMenus()
    if (stock.item) stock.item.refresh()
    return "ok"
  }

  function ping() { return "ok" }

  function quote(value) { return "'" + String(value).replace(/'/g, "'\\''") + "'" }

  // Let go of a select/input request without answering it, so its caller
  // carries on. Writing the done file is what the caller polls for.
  function release(doneFile) {
    if (doneFile) Quickshell.execDetached(["bash", "-c", ": > " + quote(doneFile)])
  }

  function releasePayload(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    release(payload.doneFile)
  }

  // Omarchy's menu has the same overwrite bug as the notch's fork had: a new
  // request replaces a pending one without answering it.
  function releaseStock() {
    if (stock.item && stock.item.requestActive && stock.item.doneFile) {
      release(stock.item.doneFile)
      stock.item.close()
    }
  }

  // The guard for an empty Apps list: a third-party clone of omarchy.menu was
  // once seen listing no apps. If the app library the host handed us has no
  // entries, Omarchy's menu gets its own instance instead, the same fallback
  // the notch's menu uses.
  QtObject { id: appsProxy; property var appLibrary: ownApps.item }
  Loader { id: ownApps; active: false; source: Quickshell.shellPath("services/AppLibrary.qml") }

  function useOwnAppsIfEmpty(payloadJson) {
    if (root.appsSource === "own") return
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    if (payload.mode === "select" || payload.mode === "input") return
    var library = root.shell ? root.shell.appLibrary : null
    var entries = 0
    try { entries = library ? library.sortedEntries("").length : 0 } catch (e) { entries = 0 }
    if (entries > 0) return
    ownApps.active = true
    root.appsSource = "own"
  }

  // Registering once, at completion, assumed the notch's bridge had already
  // resolved by then. It is a Loader over a file in ANOTHER plugin's folder, so
  // that is not something to assume: when it resolved late the notch was still
  // routed to (the `notch` binding caught up) but never learned who was doing
  // the routing, and its settings row said the companion was not installed. So
  // this registers whenever the bridge appears, however late that is.
  onBridgeChanged: if (root.bridge) root.bridge.facade = root

  Component.onCompleted: {
    root.stockFirstSource = String(stock.source)
    if (root.bridge) root.bridge.facade = root
  }

  Component.onDestruction: {
    // A reload while a picker waits would strand its caller; execDetached
    // outlives this object, a Process would not.
    if (stock.item && stock.item.requestActive && stock.item.doneFile) release(stock.item.doneFile)
    if (root.bridge && root.bridge.facade === root) root.bridge.facade = null
  }
}
