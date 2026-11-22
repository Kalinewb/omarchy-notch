import QtQuick

QtObject {
  property string path: ""
  property bool watchChanges: false
  property bool blockLoading: false
  property bool printErrors: true
  signal fileChanged()
  signal loaded()
  signal loadFailed(var error)
  function text() { return "" }
  function reload() {}
}
