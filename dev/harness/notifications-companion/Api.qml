import QtQuick
QtObject {
  property bool takeOver: true
  property real since: 1000
  // The toasts the notch has drawn, as "<timestamp>-<originalId>"; null is all of them.
  property var drawn: null
  function shows(originalId, timestamp) { return drawn === null || drawn.indexOf(timestamp + "-" + originalId) !== -1 }
}
