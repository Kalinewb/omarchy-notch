import QtQuick
import Quickshell
import Quickshell.Wayland

// A picker with the shape Omarchy's four have -- a root with `opened`, `open()`,
// `close()`, and a window holding a scrim, a click-outside catcher and a card --
// built to count what it is told and small enough that mapping its window (the
// thing the notch must prevent, and must allow again afterwards) is harmless: a
// 300 x 200 panel on the background layer with an empty input mask, where a real
// OverlayWindow would be full-screen with the keyboard.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  property bool opened: false
  property int opens: 0
  property int closes: 0
  property int escapes: 0
  property string filterText: ""
  // The same dependency the real cards have: the card is sized from the window.
  property int cardWidth: Math.min(400, win.width - 20)
  property int cardHeight: Math.min(500, win.height - 20)

  function open(payloadJson) { root.opened = true; root.opens += 1; root.filterText = "" }
  function close() { if (root.opened) root.closes += 1; root.opened = false }

  PanelWindow {
    id: win
    visible: root.opened
    anchors.top: true
    anchors.left: true
    implicitWidth: 300
    implicitHeight: 200
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "notch-overlay-fixture"

    Rectangle { anchors.fill: parent; color: "#80000000" }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Rectangle {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      anchors.centerIn: parent
      color: "#202020"
      radius: 8

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: { root.escapes += 1; root.close() }
      }

      Text {
        anchors.centerIn: parent
        color: "#ffffff"
        text: root.filterText || "Fixture picker"
      }
    }
  }
}
