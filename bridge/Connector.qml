import QtQuick
import "."

// Loaded by URL from a companion's folder, so it sees the notch's bridge
// singletons (NotchMenuBridge.qml, NotchOsdBridge.qml). Nothing else.
QtObject {
  readonly property var bridge: NotchMenuBridge
  readonly property var osdBridge: NotchOsdBridge
}
