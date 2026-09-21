import QtQuick
import qs.Ui

// Omarchy's menu button (shell/plugins/menu/BarWidget.qml, 4.0.3) under this
// plugin's id. It still toggles omarchy.menu, which Omarchy now routes here.

BarWidget {
  id: root
  moduleName: "kalinewb.notch-menu"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\ue900"
    fontFamily: "omarchy"
    horizontalMargin: 7.5
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("omarchy-shell shell toggle omarchy.menu '{\"menu\":\"root\"}'")
    }
  }
}
