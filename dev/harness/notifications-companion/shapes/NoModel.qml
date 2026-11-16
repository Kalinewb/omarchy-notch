// An Omarchy service whose list of toasts is not where the companion looks.
import QtQuick
Item {
  property var shell: null
  property alias variantsObj: variants
  QtObject {
    id: variants
    property var model: [1]
    property list<QtObject> instances: [ QtObject { property bool visible: true } ]
  }
}
