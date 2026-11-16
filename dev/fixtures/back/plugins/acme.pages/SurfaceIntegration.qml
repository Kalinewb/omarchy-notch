import QtQuick

// A plugin whose panel navigates inside itself, as Face ID's does: a stack of
// pages, a way back through them, and the first press of the notch's back
// strip taken by that stack before the notch closes anything.
Item {
  id: integration

  property var surfaceHost: null
  property bool available: true
  property Component panel: Component { PagesPanel {} }
}
