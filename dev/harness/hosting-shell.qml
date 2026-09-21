import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "notch" as Notch

// PanelHosting.qml driven against a real Omarchy bar widget, for dev/hosting.sh.
//
// The widget under test is loaded from the installed shell and given the
// smallest `bar` it actually reads. The host is a plain black window standing in
// for the notch's panel surface, so what is measured is the hosting mechanism
// and not the notch's own drawing.
ShellRoot {
  id: harness

  readonly property string widgetPath: Quickshell.env("HOSTING_WIDGET")
    || (Quickshell.env("OMARCHY_SHELL_PATH") + "/plugins/panels/audio/Panel.qml")

  // Only what the widget and its KeyboardPanel actually read.
  QtObject {
    id: fakeBar
    property var shell: null
    property color foreground: "#ffffff"
    property string fontFamily: "monospace"
    property string iconFont: "monospace"
    property int barSize: 32
    property string position: "top"
    property var iconCanvas: null
    property var iconSlot: null
    property var clickTargets: []
    property var activePopout: null
    function requestPopout(o) { return true }
    function releasePopout(o) { }
    function targetBelongsToWindow(t, w) { return false }
  }

  PanelWindow {
    id: host
    anchors.top: true
    anchors.left: true
    implicitWidth: 460
    implicitHeight: 420
    color: "#000000"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "notch-hosting-probe"

    Item { id: hostSlot; anchors.fill: parent }
  }

  Loader {
    id: widget
    asynchronous: false
    source: "file://" + harness.widgetPath
    onLoaded: if ("bar" in item) item.bar = fakeBar
  }

  Notch.PanelHosting { id: hosting }

  IpcHandler {
    target: "hosting"

    function ready(): string { return widget.item ? "yes" : "no" }

    function hostable(): string { return hosting.reasonNotHostable(widget.item) }

    function take(): string { return hosting.take(widget.item, hostSlot) }

    function giveBack(): string { return hosting.giveBack() }

    // Open the plugin's own panel the way a click on its bar icon would.
    function openOwn(): string {
      var controller = hosting.controllerOf(widget.item)
      if (!controller) return "no controller"
      controller.open = true
      return "ok"
    }

    function closeOwn(): string {
      var controller = hosting.controllerOf(widget.item)
      if (!controller) return "no controller"
      controller.open = false
      return "ok"
    }

    function resizeHost(width: int): string { host.implicitWidth = width; return "ok" }

    // Everything a check reads: what is hosted, where it is, and whether the
    // plugin's own window is mapped.
    function state(): string {
      var panel = hosting.panelOf(widget.item)
      var controller = hosting.controllerOf(widget.item)
      var body = hosting.content
      return JSON.stringify({
        hosting: hosting.active,
        slotChildren: hostSlot.children.length,
        contentInSlot: body ? (body.parent === hostSlot) : false,
        contentSize: body ? { width: Math.round(body.width), height: Math.round(body.height) } : null,
        ownWindowVisible: panel ? panel.visible === true : false,
        ownPanelOpen: panel ? panel.open === true : false,
        // What the plugin itself believes. A hosted panel is open -- that is
        // what starts the work every panel does when it opens -- while the
        // window above stays down.
        told: controller ? controller.open === true : false,
        // The fixture's own counters, when the widget under test is it.
        fixture: (widget.item && widget.item.opens !== undefined)
          ? { opens: widget.item.opens, closes: widget.item.closes,
              ticks: widget.item.ticks, workRan: widget.item.workRan }
          : null,
        report: hosting.report()
      })
    }

    // Live text from inside the panel, wherever it currently lives: proof the
    // bindings and the plugin's own model survived the move.
    function texts(): string {
      var body = hosting.content || (hosting.panelOf(widget.item)
        ? hosting.panelOf(widget.item).contentItem[0] : null)
      var out = []
      function walk(node) {
        if (!node || out.length >= 8) return
        if (node.text !== undefined && String(node.text).length > 0) out.push(String(node.text))
        var kids = node.children || []
        for (var i = 0; i < kids.length; i++) walk(kids[i])
      }
      walk(body)
      return JSON.stringify(out)
    }

    function quit(): string { Qt.quit(); return "ok" }
  }
}
