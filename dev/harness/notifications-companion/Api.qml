import QtQuick
QtObject {
  property bool takeOver: true
  // The toasts the notch has drawn, as "<key>@<ts>"; null is all of them.
  property var drawn: null
  function shows(key, ts) { return drawn === null || drawn.indexOf(key + "@" + ts) !== -1 }
}
