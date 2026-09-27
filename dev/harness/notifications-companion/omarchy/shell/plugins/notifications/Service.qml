// The shape of Omarchy's plugins/notifications/Service.qml the companion relies
// on: a popupModel alias, and a Variants-like child whose instances are
// windows bound to `popupModel.count > 0`.
import QtQuick
Item {
  id: service
  property var shell: null
  property alias popupModel: popupModel
  ListModel { id: popupModel }
  property alias variantsObj: variants
  QtObject {
    id: variants
    property var model: [1, 2]
    property list<QtObject> instances: [
      QtObject { property bool visible: popupModel.count > 0 },
      QtObject { property bool visible: popupModel.count > 0 }
    ]
  }
}
