import QtQuick

Item {
  property var surfaceHost: null
  property bool available: true
  property Component panel: Component { GuardPanel {} }
}
