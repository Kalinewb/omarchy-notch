import QtQuick

// Inert: the theme singletons declare these and the panels never start them.
QtObject {
  property var command: []
  property bool running: false
  property var stdout: null
}
