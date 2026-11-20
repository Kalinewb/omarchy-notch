import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "notch" as Notch

// OverlayHosting.qml driven against a real Omarchy picker, for dev/overlays.sh.
//
// The picker under test is loaded from the installed shell (or the sandboxed copy
// the suite makes of the clipboard, which would otherwise reap the live
// session's clipboard watchers). The host is a plain black window standing in for
// the notch's panel surface, as in hosting-shell.qml: it is held on the
// BACKGROUND layer with an empty input mask, so it costs nothing on screen.
//
// What this must never do is let the picker's own window map: a real picker's
// window is a full-screen overlay that takes the keyboard, so every check that
// opens one does it with the hold on, and a check that fails by mapping it is a
// check that has just put a scrim over the session -- which is why the suite
// closes the picker first thing on a failure.
ShellRoot {
  id: harness

  readonly property string stockPath: Quickshell.env("OVERLAY_STOCK")
  readonly property string payload: Quickshell.env("OVERLAY_PAYLOAD") || "{}"

  PanelWindow {
    id: host
    anchors.top: true
    anchors.left: true
    implicitWidth: 900
    implicitHeight: 700
    color: "#000000"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "notch-overlay-probe"

    Item { id: hostSlot; anchors.fill: parent }
  }

  Loader {
    id: stock
    asynchronous: false
    source: "file://" + harness.stockPath
    onLoaded: {
      if ("omarchyPath" in item) item.omarchyPath = Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
    }
  }

  Notch.OverlayHosting { id: hosting }

  IpcHandler {
    target: "overlay"

    function ready(): string { return stock.item ? "yes" : "no" }
    function windowFound(): string { return hosting.windowOf(stock.item) ? "yes" : "no" }
    function hostable(): string { return hosting.reasonNotHostable(stock.item) }
    function arm(): string { return hosting.arm(stock.item, "probe") }
    function disarm(): string { hosting.disarm(); return "ok" }
    function open(): string { stock.item.open(harness.payload); return "ok" }
    function closeInner(): string { stock.item.close(); return "ok" }
    function take(): string { return hosting.take(stock.item, hostSlot) }
    function giveBack(): string { return hosting.giveBack() }
    function resizeArea(width: int, height: int): string { hosting.areaWidth = width; hosting.areaHeight = height; return "ok" }
    function focus(): string { return hosting.focusContent() ? "ok" : "no target" }

    function state(): string {
      var win = hosting.windowOf(stock.item)
      var body = hosting.content
      var target = hosting.focusTarget
      return JSON.stringify({
        hosting: hosting.active,
        armed: hosting.armed,
        slotChildren: hostSlot.children.length,
        contentInSlot: body ? (body.parent === hostSlot) : false,
        contentSize: body ? { width: Math.round(body.width), height: Math.round(body.height) } : null,
        // What was left behind in the window: the scrim and the click-outside catcher.
        windowChildren: win && win.contentItem ? win.contentItem.children.length : -1,
        windowVisible: win ? win.visible === true : null,
        windowSize: win ? { width: Math.round(win.implicitWidth), height: Math.round(win.implicitHeight) } : null,
        told: stock.item ? stock.item.opened === true : false,
        focusTarget: target ? String(target).split("(")[0] : "",
        wanted: { width: Math.round(hosting.wantedWidth), height: Math.round(hosting.wantedHeight) },
        monochrome: hosting.monochrome,
        report: hosting.report()
      })
    }

    // Live text from inside the card, wherever it lives now.
    function texts(): string {
      var out = []
      function walk(node, depth) {
        if (!node || out.length >= 8 || depth > 12) return
        if (node.text !== undefined && String(node.text).length > 0) out.push(String(node.text))
        var kids = node.children || []
        for (var i = 0; i < kids.length; i++) walk(kids[i], depth + 1)
      }
      walk(hosting.content, 0)
      return JSON.stringify(out)
    }

    function quit(): string { Qt.quit(); return "ok" }
  }
}
