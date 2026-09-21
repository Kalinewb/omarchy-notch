import QtQuick
import qs.Ui

// A bar widget built exactly the way Omarchy's panels are -- Ui.Panel (which
// owns the PanelController and `opened`), a KeyboardPanel mapped by
// `open: root.opened`, a PanelKeyCatcher inside it -- and nothing else.
//
// It exists to measure what a hosted panel is TOLD, which no real panel can
// report about itself: how many times it was opened and closed, whether the
// work a panel does when it opens ran, whether its `running: opened` timers
// are ticking, and whether the keyboard reached it. Omarchy's network panel
// starts its only wifi scan in `onOpenedChanged`; a panel that is drawn but
// never opened has no networks to show, and this is that in miniature.
//
// Used by dev/hosting.sh through HOSTING_WIDGET.
Panel {
  id: root
  moduleName: "acme.hosting"
  manageIpc: false

  // What the notch is measured against.
  property int opens: 0
  property int closes: 0
  property int ticks: 0
  property int keys: 0
  property string lastKey: ""
  property bool workRan: false

  onOpenedChanged: {
    if (opened) { opens += 1; workRan = true }
    else { closes += 1; workRan = false }
  }

  // The shape of every live thing in an Omarchy panel: it runs while the panel
  // is open and stops when it is not.
  Timer {
    interval: 100
    repeat: true
    running: root.opened
    onTriggered: root.ticks += 1
  }

  implicitWidth: 20
  implicitHeight: 20

  Rectangle {
    id: button
    anchors.fill: parent
    color: "transparent"
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: 200
    contentHeight: 120

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function (dx, dy) { root.keys += 1; root.lastKey = "move" }
      onActivateRequested: { root.keys += 1; root.lastKey = "activate" }
      onCloseRequested: { root.keys += 1; root.lastKey = "close"; root.close() }
      onTextKey: function (text) { root.keys += 1; root.lastKey = text }

      Text {
        anchors.centerIn: parent
        text: "hosted fixture · opens " + root.opens
        color: "#ffffff"
      }
    }
  }
}
