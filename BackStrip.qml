import QtQuick

// The way back at the top centre of an open panel: press anywhere in the zone to go back one step.
//
// It is an AREA, not a button. Nothing is drawn: no chevron, no pill, no border, no wash, no focus
// box -- it blends into the notch and the panel under it, and the notch looks the same with it as
// without. The only sign of it is the pointer, which becomes a hand over the zone. It is the notch's
// one back control; Esc is its invisible alias (SURFACE-HOSTING.md section 15). For a screen reader
// it is a button named "Back".
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

  // The one thing that says "press here", and it is not drawn.
  HoverHandler { cursorShape: Qt.PointingHandCursor }
}
