import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Can another plugin's panel content be taken out of its own window, drawn
// inside ours, and given back?
//
// This is the experiment behind plan-adapters.md's "panel hosting", run before
// anything was built on the answer. The subject is Omarchy's REAL audio widget,
// loaded from the installed shell; nothing here is the notch.
//
//   ln -s $OMARCHY_PATH/shell/{Commons,Ui,services} <root>/
//   cp dev/harness/reparent-probe.qml <root>/shell.qml
//   OMARCHY_SHELL_PATH=$OMARCHY_PATH/shell quickshell -p <root> -n
//
// Stages: an empty black host window (STAGE1), the content moved into it
// (STAGE2), the host resized to prove the layout still answers (STAGE3), then
// the content put back and the plugin's own panel opened normally (STAGE4).
// Screenshot the top-left 460x420 on each side of the move to see it.
//
// Measured 2026-09-18:
//   empty host          0 non-black pixels of 193 200, exactly 1 colour
//   hosting the panel   12 013 non-black pixels, 1 546 colours
//   live                the moved tree reported "STEADY GROOVE", "55%" etc.
//                       straight from the audio service
//   relayout            inner width followed the host, 460 -> 640
//   given back          parent restored, host emptied (0 children), the
//                       plugin's own panel opened and was visible, and the
//                       content still reported live text
//   the plugin's own window never mapped while the notch held its content
//
// One caveat the return exposed: clearing `anchors.fill` leaves the item at the
// host's size (640x420 here), so whatever hosts a panel has to put the original
// sizing back rather than assume the plugin will.
ShellRoot {
  id: harness

  // The smallest `bar` the widget and its KeyboardPanel actually read.
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

  // Our own surface, standing in for the notch's panel window.
  PanelWindow {
    id: host
    anchors.top: true
    anchors.left: true
    implicitWidth: 460
    implicitHeight: 420
    color: "#000000"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "reparent-probe"

    Item { id: hostSlot; anchors.fill: parent }
  }

  // The widget itself, off to one side, never shown.
  Loader {
    id: widget
    asynchronous: false
    source: "file://" + Quickshell.env("OMARCHY_SHELL_PATH") + "/plugins/panels/audio/Panel.qml"
    onLoaded: { if ("bar" in item) item.bar = fakeBar }
  }

  function findPanel(node) {
    if (!node) return null
    var kids = node.children || []
    for (var i = 0; i < kids.length; i++) {
      var k = kids[i]
      if (k && k.toString().indexOf("KeyboardPanel") === 0) return k
      var deeper = findPanel(k)
      if (deeper) return deeper
    }
    return null
  }

  property var panel: null
  property var content: null
  property var moved: []
  property int widthBefore: -1
  property var origin: null

  // Give it back: the content returns to the plugin's own panel, and the
  // plugin's own window is opened normally. This is the "switch the
  // integration off" path, which the first probe never exercised.
  Timer {
    id: returnTimer
    interval: 900; repeat: false
    onTriggered: {
      var content = harness.moved[0]
      content.anchors.fill = undefined
      content.parent = harness.origin
      console.log("PROBE returned parentIsOrigin=" + (content.parent === harness.origin)
        + " hostChildren=" + hostSlot.children.length)
      // Open the plugin's own panel, the way a click on its bar icon would.
      var controller = null
      var bag = widget.item.data || []
      for (var i = 0; i < bag.length; i++)
        if (String(bag[i]).indexOf("PanelController") === 0) controller = bag[i]
      console.log("PROBE controllerFound=" + (controller !== null))
      if (controller) controller.open = true
      settleTimer.start()
    }
  }

  Timer {
    id: settleTimer
    interval: 1200; repeat: false
    onTriggered: {
      var content = harness.moved[0]
      function texts(node, out) {
        if (!node) return out
        if (node.text !== undefined && String(node.text).length > 0 && out.length < 6) out.push(String(node.text))
        var kids = node.children || []
        for (var i = 0; i < kids.length; i++) texts(kids[i], out)
        return out
      }
      console.log("PROBE afterReturn panelOpen=" + harness.panel.open
        + " panelVisible=" + harness.panel.visible
        + " contentSize=" + Math.round(content.width) + "x" + Math.round(content.height))
      console.log("PROBE afterReturn texts=" + JSON.stringify(texts(content, [])))
      console.log("PROBE STAGE4 returned")
    }
  }

  Timer {
    id: relayoutTimer
    interval: 700; repeat: false
    onTriggered: {
      var content = harness.moved[0]
      var after = content.children.length > 0 ? Math.round(content.children[0].width) : -1
      console.log("PROBE relayout innerWidth " + harness.widthBefore + " -> " + after
        + " (host " + host.width + ")")
      console.log("PROBE STAGE3 done")
      returnTimer.start()
    }
  }

  // The move itself, after a screenshot of the empty host.
  Timer {
    id: moveTimer
    interval: 2200; repeat: false
    onTriggered: {
      var content = harness.content
      content.parent = hostSlot
      content.anchors.fill = hostSlot
      harness.moved = [content]
      console.log("PROBE after parentIsHost=" + (content.parent === hostSlot)
        + " hostChildren=" + hostSlot.children.length)
      reportTimer.start()
    }
  }

  // After a beat, say what the moved content looks like where it now lives.
  Timer {
    id: reportTimer
    interval: 1400; repeat: false
    onTriggered: {
      var content = harness.moved.length > 0 ? harness.moved[0] : null
      if (!content) { Qt.quit(); return }
      console.log("PROBE settled size=" + Math.round(content.width) + "x" + Math.round(content.height)
        + " visible=" + content.visible + " opacity=" + content.opacity
        + " childCount=" + content.children.length
        + " window=" + (content.Window && content.Window.window ? "yes" : "unknown"))
      console.log("PROBE hostVisible=" + host.visible + " hostSize=" + host.width + "x" + host.height)
      // Is it alive, or just pixels? Walk the moved tree for text the audio
      // service supplies, and watch the layout answer a size change.
      function texts(node, out) {
        if (!node) return out
        if (node.text !== undefined && String(node.text).length > 0 && out.length < 8) out.push(String(node.text))
        var kids = node.children || []
        for (var i = 0; i < kids.length; i++) texts(kids[i], out)
        return out
      }
      console.log("PROBE live texts=" + JSON.stringify(texts(content, [])))
      var before = content.children.length > 0 ? Math.round(content.children[0].width) : -1
      host.implicitWidth = 640
      relayoutTimer.start()
      harness.widthBefore = before
      console.log("PROBE STAGE2 content is in the host")
    }
  }

  Timer {
    interval: 1200; running: true; repeat: false
    onTriggered: {
      var item = widget.item
      console.log("PROBE widgetLoaded=" + (item !== null) + " status=" + widget.status)
      if (!item) { Qt.quit(); return }

      // A window declared inside an Item is not a visual child; it lands in
      // `data` with everything else declared there.
      var found = null
      var bag = item.data || []
      console.log("PROBE dataCount=" + bag.length)
      for (var i = 0; i < bag.length; i++) {
        var entry = bag[i]
        var name = String(entry)
        if (i < 40) console.log("PROBE data[" + i + "]=" + name.split("(")[0])
        if (name.indexOf("KeyboardPanel") === 0) found = entry
      }
      harness.panel = found
      console.log("PROBE panelFound=" + (found !== null) + " type=" + (found ? String(found).split("(")[0] : ""))
      if (!found) { Qt.quit(); return }

      harness.content = found.contentItem && found.contentItem.length > 0 ? found.contentItem[0] : null
      var content = harness.content
      harness.origin = content ? content.parent : null
      console.log("PROBE panelContentChildren=" + (found.contentItem ? found.contentItem.length : -1))
      if (!content) { Qt.quit(); return }

      console.log("PROBE before parentIsPanel=" + (content.parent !== null)
        + " size=" + Math.round(content.width) + "x" + Math.round(content.height)
        + " visible=" + content.visible + " childCount=" + content.children.length)

      console.log("PROBE STAGE1 empty host is up")
      moveTimer.start()
    }
  }
}
