import QtQuick

// The way back at the top centre of an open panel: press anywhere in the zone to go back one step.
//
// The whole zone is the target and it is a pointer-sensitive AREA, not a button. At rest nothing is
// drawn: the notch looks the same with it as without. Under the pointer a small back chevron fades in
// at the centre of the zone -- a mark, with no pill, border, box or wash -- and the pointer becomes a
// hand over the whole zone. It is there only while there is a step to take (`offered`), and with
// reduced motion it appears without the fade. It is the notch's one back control; Esc is its
// invisible alias (SURFACE-HOSTING.md section 15). For a screen reader it is a button named "Back".
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
  // What the chevron is drawn with; the host sets them (Bar.qml).
  property color foreground: "#ffffff"
  property string fontFamily: ""
  property real glyphSize: 14
  property bool reducedMotion: false
  // Whether the pointer is over the zone, and how visible the chevron is as a result: what a test reads.
  readonly property bool hovered: hover.hovered
  readonly property real chevronOpacity: chevron.opacity

  signal activated()

  visible: offered
  enabled: offered

  Accessible.role: Accessible.Button
  Accessible.name: "Back"
  Accessible.onPressAction: strip.activated()

  // An exclusive grab on the press. The default policy only takes a passive one,
  // and the island under this strip has a TapHandler of its own: both would see
  // the tap, so a press that closed the panel was then also the notch's click,
  // which opens the widgets again -- and the press seemed to do nothing.
  TapHandler {
    acceptedButtons: Qt.LeftButton
    gesturePolicy: TapHandler.WithinBounds
    onSingleTapped: strip.activated()
  }

  // The pointer over the zone: the hand says "press here", and the chevron says what the press does.
  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }

  Text {
    id: chevron
    objectName: "backChevron"
    anchors.centerIn: parent
    text: "‹"
    color: strip.foreground
    font.family: strip.fontFamily
    font.pixelSize: strip.glyphSize
    opacity: hover.hovered ? 0.75 : 0
    Behavior on opacity { enabled: !strip.reducedMotion; NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
  }
}
