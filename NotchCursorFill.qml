import QtQuick
import qs.Commons

// The row cursor's mark on a page (Settings, Setup): NotchButton's focus fill,
// in the shape of the row it sits behind.
Rectangle {
  // The page: foreground and radiusFor().
  property var page: null
  anchors.fill: parent
  z: -1
  radius: page ? page.radiusFor(Math.min(width, height)) : 0
  color: page ? Util.alpha(page.foreground, Style.focusFillAlpha) : "transparent"
}
