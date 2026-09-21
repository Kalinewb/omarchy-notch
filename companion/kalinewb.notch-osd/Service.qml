import QtQuick
import Quickshell
import Quickshell.Io

// The go-between for Omarchy's on-screen display.
//
// A SERVICE, not just the panel entry point: Omarchy builds a panel plugin's
// entry point when something summons it, and the CLI never summons. Every
// volume and brightness key runs `omarchy-osd`, which calls
// `omarchy-shell osd show <payload>` against the `osd` IPC target directly --
// so if this only existed while a panel was open, the keys would find nothing
// there and the notch would never see them. A service is loaded when the shell
// starts and stays, so the target is owned from the first key press.
//
// This plugin says `clonedFrom: omarchy.osd`, so Omarchy sends every OSD call
// here: the volume and brightness keys, the media buttons, anything else that
// calls `summon("omarchy.osd", …)`. Each call is handed to whichever can serve
// it:
//
//   the notch    when a notch is running here, its "Show the OSD in the notch"
//                setting is on, and it is in a state to show one
//   Omarchy's    otherwise -- loaded from $OMARCHY_PATH by URL, so it is the
//   own OSD      real card, not a copy, and it keeps following Omarchy
//
// A key press must never do nothing. The notch answers "shown" or
// "declined:<reason>", and anything but "shown" falls through to Omarchy's own
// card -- so with a panel open, the bar hidden, or no notch running, pressing
// volume still shows volume.
//
// It reaches the notch through the notch's own bridge singleton, loaded by URL
// from the notch's folder; a missing or mismatched notch just means Omarchy's
// OSD.
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
  // "notch" or "stock": who took the last one, for the notch's report.
  property string route: ""
  // Why the notch turned the last one down, in its own words.
  property string declined: ""
  property string stockError: ""

  // Omarchy's own OSD, loaded only once something actually needs it.
  //
  // Lazily on purpose, and it is not about cost. Omarchy's Osd.qml registers
  // `IpcHandler { target: "osd" }`, and that target is how the CLI reaches an
  // OSD: `omarchy-osd` -- which is what every volume and brightness key
  // runs -- calls `omarchy-shell osd show <payload>` directly rather than
  // going through `summon`, so it never passes the clone resolution that sends
  // everything else here. Enabling this companion disables `omarchy.osd`, so
  // that target is free; loading Omarchy's file eagerly handed it straight
  // back, and a volume key went to the card this plugin had loaded for its own
  // fallback instead of to the notch.
  //
  // So the go-between owns `osd` (below) and the card is loaded the first time
  // a fallback is really needed.
  property bool stockWanted: false
  Loader {
    id: stock
    active: root.stockWanted
    asynchronous: false
    source: Quickshell.env("NOTCH_OSD_STOCK_URL") || ("file://" + root.omarchyPath + "/shell/plugins/osd/Osd.qml")
    onStatusChanged: {
      if (status === Loader.Error) root.stockError = String(sourceComponent ? sourceComponent.errorString() : "could not load Omarchy's OSD")
      else if (status === Loader.Ready) root.stockError = ""
    }
  }

  // The notch's bridge. A missing notch folder is a Loader error and nothing else.
  Loader {
    id: link
    asynchronous: false
    source: Quickshell.env("NOTCH_OSD_CONNECTOR_URL") || Qt.resolvedUrl("../kalinewb.notch/bridge/Connector.qml")
  }
  readonly property var stockItem: stock.item
  readonly property var bridge: link.item ? link.item.osdBridge : null
  readonly property int expectedApi: Number(Quickshell.env("NOTCH_OSD_BRIDGE_API") || apiVersion)
  readonly property var notch: {
    if (!bridge || Number(bridge.apiVersion) !== expectedApi) return null
    var target = bridge.target
    return target && typeof target.showOsd === "function" ? target : null
  }

  // What the shell reads to know whether this is up.
  readonly property bool opened: (notch && notch.notchReplaceOsd && notch.osdShown)
    || (stock.item ? stock.item.opened === true : false)

  // --- Omarchy's plugin lifecycle ----------------------------------------------

  function open(payloadJson) {
    if (root.notch && root.notch.notchReplaceOsd) {
      var answer = String(root.notch.showOsd(payloadJson) || "")
      if (answer === "shown") {
        // One event, one display: Omarchy's card must not be left up under the
        // notch's from a previous call it did take.
        if (stock.item) stock.item.close()
        root.declined = ""
        root.route = "notch"
        return
      }
      root.declined = answer
    }
    // And the other way round: the notch must not keep showing one while
    // Omarchy's card answers the same key.
    if (root.notch) root.notch.hideOsd()
    root.stockWanted = true
    if (stock.item) {
      stock.item.open(payloadJson)
      root.route = "stock"
      return
    }
    console.warn("kalinewb.notch-osd: nothing to show an OSD with"
      + (root.stockError ? " (" + root.stockError + ")" : ""))
  }

  function close() {
    if (root.notch) root.notch.hideOsd()
    if (stock.item) stock.item.close()
  }

  // The CLI's way in. `omarchy-osd` -- and so every volume and brightness
  // key -- calls `omarchy-shell osd show <payload>` against this target rather
  // than summoning the plugin, so without this the keys never reach the notch
  // however the routing is set up. Same verbs as Omarchy's own, so nothing
  // that calls it can tell the difference.
  IpcHandler {
    target: "osd"
    function show(payloadJson: string): string { root.open(payloadJson); return "ok" }
    function close(): string { root.close(); return "ok" }
    function state(): string { return root.opened ? "open" : "closed" }
    function ping(): string { return "ok" }
  }

  // The notch's report reads this, so a companion that is loaded can say what
  // it is and where the last call went.
  // The notch's report reads `facade`; the panel entry point reads `service`
  // to forward what it is handed.
  Component.onCompleted: {
    if (bridge) { bridge.facade = root; bridge.service = root }
  }
  Component.onDestruction: {
    if (bridge && bridge.facade === root) bridge.facade = null
    if (bridge && bridge.service === root) bridge.service = null
  }
}
