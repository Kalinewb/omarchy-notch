import QtQuick

// Inert: the theme singletons declare these and the panels never start them.
// (`exited` and `exitCode` are there so a page that listens for a run, like
// the Share and Import rows, loads.)
QtObject {
  property var command: []
  property bool running: false
  property var stdout: null
  property int exitCode: 0
  signal exited(int exitCode, int exitStatus)
}
