import QtQuick

// Whichever hosting is drawing the notch's guest, behind the one interface
// Bar.qml already reads (PanelHosting's).
//
// There are two kinds of guest and they are taken differently: a bar widget's
// pop-out panel (PanelHosting.qml: a KeyboardPanel and a controller, found by
// walking the widget) and a window-based plugin's card (OverlayHosting.qml:
// armed first, by the plugin's own go-between, so its window never maps). The
// notch has one hosted slot and one question to ask -- what is open, how big
// does it want to be, take it, give it back -- so this answers it for whichever
// is. A guest is a widget unless it was armed as an overlay.
QtObject {
  id: router

  property var panels: null
  property var overlays: null

  readonly property var current: overlays && overlays.active ? overlays : panels

  readonly property bool active: (!!panels && panels.active) || (!!overlays && overlays.active)
  readonly property var widget: current ? current.widget : null
  readonly property var content: current ? current.content : null
  readonly property var panel: current ? current.panel : null
  readonly property var controller: current ? current.controller : null
  readonly property var taken: current ? current.taken : []
  readonly property var focusTarget: current ? current.focusTarget : null
  readonly property real wantedWidth: current ? current.wantedWidth : 0
  readonly property real wantedHeight: current ? current.wantedHeight : 0
  // Whether the hosted guest keeps its own colours. A panel is drawn through the
  // notch's monochrome transform; a picker's content is not chrome.
  readonly property bool monochrome: !(overlays && overlays.active)

  function isOverlay(item) { return !!overlays && overlays.owns(item) }

  function reasonNotHostable(item) {
    return isOverlay(item) ? overlays.reasonNotHostable(item) : panels.reasonNotHostable(item)
  }
  function hostable(item) { return reasonNotHostable(item) === "" }

  function take(item, slot) {
    return isOverlay(item) ? overlays.take(item, slot) : panels.take(item, slot)
  }

  function giveBack() {
    var answer = ""
    if (overlays && overlays.active) answer = overlays.giveBack()
    if (panels && panels.active) answer = panels.giveBack()
    return answer
  }

  function focusContent() { return current ? current.focusContent() : false }

  // What only a bar widget has.
  function controllerOf(item) { return panels.controllerOf(item) }
  function panelOf(item) { return panels.panelOf(item) }

  function report() { return current ? current.report() : panels.report() }
}
