import QtQuick
import qs.Commons

// A button on one of the notch's pages (Settings, Setup, Plugins): the page's
// colours, radius and font, reached by Tab, and the page's foot line cleared
// when it is pressed. The default is the bordered look of a row's action;
// `header` is the borderless look of a page's title row.
NotchButton {
  id: button
  // The page: foreground, accent, fontFamily, radiusFor() and its foot line `tip`.
  property var page: null
  property bool header: false

  foreground: page ? page.foreground : "#ffffff"
  accent: page ? page.accent : foreground
  radius: page ? page.radiusFor(Math.min(width, height)) : Math.min(width, height) / 2
  fontFamily: page ? page.fontFamily : Style.font.family
  fontSize: header ? Style.font.body : Style.font.bodySmall
  horizontalPadding: Style.space(header ? 10 : 7)
  bordered: !header
  focusable: true
  onClicked: if (page && page.tip) page.tip.hide()
}
