import QtQuick
// A popup window as Omarchy 4.5 draws one: the three properties the companion
// reads, and a `visible` bound the way Omarchy binds it.
QtObject {
  property bool showingNotifications: true
  property bool stepAside: false
  property bool hasSomethingToShow: false
  property bool visible: !stepAside || hasSomethingToShow
}
