// The shape of Omarchy 4.5's plugins/notifications/Service.qml the companion
// relies on: a ListModel of rows (key, ts, ...) among the service's children,
// not exposed as a property, and a Variants-like child whose instances are
// windows with `visible: !stepAside || hasSomethingToShow`.
import QtQuick
Item {
  id: service
  property var shell: null
  // What the notch calls on a click.
  property var calls: []
  function rowIndexFor(key) {
    for (var i = 0; i < toasts.count; i++) if (toasts.get(i).key === key) return i
    return -1
  }
  function activate(key, instant) { calls = calls.concat(["activate " + key]) }
  function closeToast(key, reason, instant) { calls = calls.concat(["close " + key + " " + reason]) }
  property alias variantsObj: variants

  ListModel { id: toasts }
  // The test reaches the model through here; the real service has no such door.
  property alias modelForTest: toasts

  QtObject {
    id: variants
    property var model: [1, 2]
    property list<QtObject> instances: [
      QtObject {
        property bool showingNotifications: true
        property bool stepAside: false
        property bool hasSomethingToShow: showingNotifications && toasts.count > 0
        property bool visible: !stepAside || hasSomethingToShow
      },
      QtObject {
        property bool showingNotifications: true
        property bool stepAside: false
        property bool hasSomethingToShow: showingNotifications && toasts.count > 0
        property bool visible: !stepAside || hasSomethingToShow
      }
    ]
  }
}
