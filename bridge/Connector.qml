import QtQuick
import "."

// Loaded by URL from the menu companion's folder, so it sees the notch's
// NotchMenuBridge singleton (see NotchMenuBridge.qml). Nothing else.
QtObject {
  readonly property var bridge: NotchMenuBridge
}
