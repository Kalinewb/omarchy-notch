import QtQuick

// The route says where the controls are:
//   clear     a button in a header that starts below the zone, as the contract asks
//   gutter    a button in the row of the zone, but beside it (left of it), not in it
//   label     text in the middle of the zone: not a control, but a collision of the other kind
//   leftTitle a short title at the left of a full-width box that spans the zone: it paints beside it, no collision
//   button    a button in the middle of the zone
//   mouse     a bare MouseArea over part of the zone
//   tap       an item with a TapHandler over part of the zone
//   input     a text input in the zone
//   hidden    a button in the zone that is not visible: not a collision
//   backdrop  a panel-sized MouseArea under everything: the panel's own surface, not a control
//   scrolled  a list that starts below the zone, scrolled up: a row and its text sit under the zone but
//             the list clips them away, so nothing is drawn there (scrolledNoClip: the same, not clipped)
Item {
  id: panel

  property var surfaceHost: null
  property string surfaceScreen: ""
  property string route: "clear"
  property real maxWidth: 400
  property real maxHeight: 400
  signal closeRequested()

  readonly property real zoneHeight: surfaceHost ? surfaceHost.backZoneHeight : 32
  readonly property real zoneWidth: surfaceHost ? surfaceHost.backZoneWidth : 180
  readonly property string kind: String(route).split(":")[0]

  implicitWidth: 320
  implicitHeight: 200

  // The host's answer, written down for dev/backone.sh.
  function open(next) { console.log("ZONE " + Math.round(zoneWidth) + "x" + Math.round(zoneHeight)) }

  MouseArea { visible: panel.kind === "backdrop"; anchors.fill: parent }

  Rectangle {
    objectName: "headerButton"
    visible: panel.kind === "clear" || panel.kind === "gutter" || panel.kind === "button" || panel.kind === "hidden"
    x: panel.kind === "gutter" ? 4 : (panel.width - width) / 2
    y: panel.kind === "clear" ? panel.zoneHeight + 4 : 2
    width: panel.kind === "gutter" ? 48 : 60; height: 24
    color: "#444444"
    opacity: panel.kind === "hidden" ? 0 : 1
    MouseArea { objectName: "headerMouse"; anchors.fill: parent }
  }

  Text {
    visible: panel.kind === "label"
    text: "a title in the zone"
    color: "#ffffff"
    anchors.horizontalCenter: parent.horizontalCenter
    y: 4
  }

  Text {
    visible: panel.kind === "leftTitle"
    width: panel.width
    horizontalAlignment: Text.AlignLeft
    text: "A title"
    color: "#ffffff"
    y: 4
  }

  MouseArea {
    objectName: "bareMouse"
    visible: panel.kind === "mouse"
    x: panel.width / 2 - 10; y: 0; width: 20; height: 20
  }

  Item {
    objectName: "tapItem"
    visible: panel.kind === "tap"
    x: panel.width / 2 - 10; y: 0; width: 20; height: 20
    TapHandler { }
  }

  TextInput {
    objectName: "input"
    visible: panel.kind === "input"
    x: panel.width / 2 - 20; y: 4; width: 40
    text: "x"
  }

  Item {
    visible: panel.kind === "scrolled" || panel.kind === "scrolledNoClip"
    clip: panel.kind === "scrolled"
    x: 0; y: panel.zoneHeight; width: panel.width; height: 120
    Rectangle {
      objectName: "scrolledRow"
      x: (panel.width - width) / 2; y: -20; width: 120; height: 28
      color: "#444444"
      MouseArea { anchors.fill: parent }
      Text { anchors.centerIn: parent; text: "a row scrolled up"; color: "#ffffff" }
    }
  }
}
