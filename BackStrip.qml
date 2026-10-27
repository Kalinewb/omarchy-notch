import QtQuick

// The strip at the top centre of an open panel: press it to go back one step.
//
// A press target over a gap in the page, not over anyone's control (see the
// comment where Bar.qml places it). Its own file so the press can be tested on
// its own, under a parent that handles taps the way the notch's island does
// (dev/back.sh).
Item {
  id: strip

  // Whether there is a step to take. Off, the strip is not there at all and a
  // press goes to whatever is under it.
  property bool offered: false
  property color foreground: "#ffffff"
  property string fontFamily: ""
  property real glyphSize: 14

  signal activated()

  visible: offered
  enabled: offered

  HoverHandler { id: hover }
  // An exclusive grab on the press. The default policy only takes a passive one,
  // and the island under this strip has a TapHandler of its own: both would see
  // the tap, so a press that closed the panel was then also the notch's click,
  // which opens the widgets again -- and the press seemed to do nothing.
  TapHandler {
    acceptedButtons: Qt.LeftButton
    gesturePolicy: TapHandler.WithinBounds
    onSingleTapped: strip.activated()
  }

  // A chevron, and only under the pointer: the strip is a gap in the page the
  // rest of the time, and a mark parked in it would be a control the page never
  // asked for.
  Text {
    anchors.centerIn: parent
    text: "‹"
    color: strip.foreground
    font.family: strip.fontFamily
    font.pixelSize: strip.glyphSize
    opacity: hover.hovered ? 0.75 : 0
    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
  }
}
