import QtQuick
import Quickshell

// The go-between for one of Omarchy's pickers: the clipboard, the emoji picker,
// the image picker, the reminder flow. This one file is the same in all four
// companions; which picker it stands in for comes from the manifest's
// `clonedFrom`.
//
// Omarchy sends every call for that picker here, so each one is handed to
// whichever can serve it:
//
//   the notch   when a notch is running here, the user has asked for this
//               picker to open in it (Settings → Integrations, or
//               `bar.notch.hostedOverlays`), and it is in a state to show one
//   Omarchy's   otherwise -- loaded from $OMARCHY_PATH by URL, so it is the real
//   own picker  thing and not a copy, and it opens in its own window as always
//
// Hosting is a hold and a move, not a rewrite: the notch keeps the picker's own
// window from mapping and draws the picker's card in itself (OverlayHosting.qml).
// The picker still believes it is open, still runs its own code and receives the
// keys, and the notch gives the card back when it is done.
//
// It reaches the notch through the notch's bridge singleton, loaded by URL from
// the notch's folder; a missing or mismatched notch just means Omarchy's picker.
Item {
  id: root
  visible: false

  // Injected by the host after this is created.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property int apiVersion: 1
  readonly property string version: manifest && manifest.version ? String(manifest.version) : ""
  readonly property string sourceId: manifest && manifest.omarchy ? String(manifest.omarchy.clonedFrom || "") : ""
  // "notch" or "stock": who took the last open, for the notch's report.
  property string route: ""

  readonly property var stockFiles: ({
    "omarchy.clipboard": "clipboard/Clipboard.qml",
    "omarchy.emojis": "emojis/Emojis.qml",
    "omarchy.image-picker": "image-picker/ImagePicker.qml",
    "omarchy.reminders": "reminders/ReminderFlow.qml"
  })

  // Omarchy's own picker. Its window only maps while it is open, so loading it
  // costs nothing until it is used. Not loaded until the host has said which
  // plugin this is.
  Loader {
    id: stock
    asynchronous: false
    source: Quickshell.env("NOTCH_OVERLAY_STOCK_URL")
      || (root.stockFiles[root.sourceId] ? "file://" + root.omarchyPath + "/shell/plugins/" + root.stockFiles[root.sourceId] : "")
    onLoaded: {
      // What the host injects into a picker's entry point, handed on. The id the
      // picker hides itself under is this plugin's: that is the entry the shell
      // knows is open.
      if ("omarchyPath" in item) item.omarchyPath = Qt.binding(function () { return root.omarchyPath })
      if ("shell" in item) item.shell = Qt.binding(function () { return root.shell })
      if ("manifest" in item) item.manifest = Qt.binding(function () { return root.manifest })
    }
  }

  // The notch's bridge. A missing notch folder is a Loader error and nothing else.
  Loader {
    id: link
    asynchronous: false
    source: Quickshell.env("NOTCH_OVERLAY_CONNECTOR_URL") || Qt.resolvedUrl("../kalinewb.notch/bridge/Connector.qml")
  }
  readonly property var inner: stock.item
  readonly property var bridge: link.item ? link.item.overlayBridge : null
  readonly property int expectedApi: Number(Quickshell.env("NOTCH_OVERLAY_BRIDGE_API") || apiVersion)
  readonly property var notch: {
    if (!bridge || Number(bridge.apiVersion) !== expectedApi) return null
    var target = bridge.target
    return target && typeof target.wants === "function" ? target : null
  }

  // What the shell's toggle reads.
  readonly property bool opened: !!inner && inner.opened === true

  // The picker is open but the notch has not been asked yet: the image picker
  // scans before it opens, so `open()` returns with `opened` still false.
  property bool awaiting: false

  // Omarchy's plugin lifecycle.
  function open(payloadJson) {
    if (!inner) { console.warn("kalinewb.notch-overlay: no picker to open for " + sourceId); return }
    var hold = !!notch && notch.wants(sourceId)
    // A hold left from an earlier open the notch no longer wants.
    if (!hold && notch) notch.disarm(inner)
    // Held down BEFORE the picker opens: opening sets the state its window maps
    // from, so a hold taken after would let it map for a frame.
    if (hold) hold = notch.arm(inner, sourceId) === ""
    inner.open(payloadJson)
    if (!hold) { awaiting = false; route = "stock"; return }
    // Asked for again while the notch already shows it: the picker has reset
    // itself, which is all that was wanted.
    if (notch.hosting(inner)) { route = "notch"; return }
    if (inner.opened === true) present()
    else awaiting = true
  }

  function present() {
    awaiting = false
    var answer = String(notch.host(inner, sourceId))
    if (answer === "opened") { route = "notch"; return }
    // The notch could not draw it (away, no screen, nothing in the window): the
    // hold ends, and the picker maps its own window, exactly as it would have.
    notch.disarm(inner)
    route = "stock"
  }

  function close() { awaiting = false; if (inner) inner.close() }

  function ping() { return "ok" }

  // The picker opened later than it was asked to, or closed itself -- its Escape,
  // a pick, its own timeout. The notch's copy goes with it, down the same way as
  // the back strip takes it down.
  Connections {
    target: root.inner
    ignoreUnknownSignals: true
    function onOpenedChanged() {
      if (!root.inner || !root.notch) return
      if (root.inner.opened === true) { if (root.awaiting) root.present() }
      else { root.awaiting = false; root.notch.release(root.inner) }
    }
  }

  // Registered whenever the bridge appears, however late (the menu companion's
  // comment on this is the reason).
  onBridgeChanged: if (root.bridge) root.bridge.register(root.sourceId, root)
  onSourceIdChanged: if (root.bridge && root.sourceId) root.bridge.register(root.sourceId, root)

  Component.onCompleted: if (root.bridge && root.sourceId) root.bridge.register(root.sourceId, root)

  Component.onDestruction: {
    if (root.notch && root.inner) root.notch.release(root.inner)
    if (root.bridge) root.bridge.unregister(root.sourceId, root)
  }
}
