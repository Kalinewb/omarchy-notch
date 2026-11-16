// Two lists that could each be the toasts: the companion does not guess.
import QtQuick
Item {
  property var shell: null
  property alias variantsObj: variants
  ListModel { id: one }
  ListModel { id: two }
  QtObject {
    id: variants
    property var model: [1]
    property list<QtObject> instances: [ QtObject { property bool visible: true } ]
  }
}
