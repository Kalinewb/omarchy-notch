import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The notch's settings dropdown, opened by a long right-click on the notch.
//
// Every control reads the live value from the bar and writes straight to
// `bar.notch` in shell.json through `bar.setNotchSetting`, so a change shows
// on the notch at once and survives a restart. The battery preview is the one
// thing that is not saved: it only simulates a battery state while chosen.
PopupCard {
  id: root

  // `bar` (from PopupCard) is the notch's Bar.qml root.
  readonly property color foreground: Color.foreground
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.6)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int rowHeight: Style.space(34)

  function set(key, value) {
    if (bar) bar.setNotchSetting(key, value)
  }

  function toggleItem(key, current, item) {
    var next = current.slice()
    var i = next.indexOf(item)
    if (i === -1) next.push(item)
    else next.splice(i, 1)
    // Keep a stable order, whatever order they were switched on in.
    var order = ["clock", "date", "media", "battery"]
    next.sort(function(a, b) { return order.indexOf(a) - order.indexOf(b) })
    set(key, next)
  }

  function resetAll() {
    if (!bar || !bar.shell || typeof bar.shell.mutateShellConfig !== "function") return
    bar.batterySimulatedState = ""
    bar.shell.mutateShellConfig(function(config) {
      if (Util.isPlainObject(config.bar)) delete config.bar.notch
    })
  }

  padding: Style.space(14)
  contentWidth: fittedContentWidth(Style.space(360))
  contentHeight: fittedContentHeight(column.implicitHeight, Style.space(640))

  // The theme's popup card can be translucent, and nothing blurs behind this
  // popup, so back the menu with the notch's own black for legibility.
  Rectangle {
    anchors.fill: parent
    anchors.margins: -root.padding
    radius: Math.max(0, Style.cornerRadius - 1)
    color: root.bar ? Qt.rgba(root.bar.notchColor.r, root.bar.notchColor.g, root.bar.notchColor.b, 0.94) : "#f0000000"
  }

  Flickable {
    anchors.fill: parent
    contentWidth: width
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: column
      width: parent.width
      spacing: Style.space(2)

      Text {
        text: "Notch"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        bottomPadding: Style.space(6)
      }

      // --- behaviour ---------------------------------------------------------

      PanelSectionHeader { text: "Behaviour"; fontFamily: root.fontFamily; width: parent.width }

      SettingRow {
        label: "Opens on"
        ButtonGroup {
          options: [{ value: "hover", label: "Hover" }, { value: "click", label: "Click" }]
          value: root.bar ? root.bar.notchExpandOn : "hover"
          fontFamily: root.fontFamily
          onChanged: function(value) { root.set("expandOn", value) }
        }
      }

      SettingRow {
        label: "Windows reach the top edge"
        ToggleSwitch {
          checked: root.bar ? root.bar.notchWindowsToTop : false
          onToggled: root.set("windowsToTop", !checked)
        }
      }

      SettingRow {
        label: "Peek on a new track"
        ToggleSwitch {
          checked: root.bar ? root.bar.notchPeekOnTrackChange : true
          onToggled: root.set("peekOnTrackChange", !checked)
        }
      }

      // --- what it shows -------------------------------------------------------

      PanelSeparator { width: parent.width }
      PanelSectionHeader { text: "Shows"; fontFamily: root.fontFamily; width: parent.width }

      SettingRow {
        label: "At rest"
        ItemChips {
          selected: root.bar ? root.bar.notchCompactItems : []
          onPicked: function(item) { root.toggleItem("compact", root.bar.notchCompactItems, item) }
        }
      }

      SettingRow {
        label: "When open"
        ItemChips {
          selected: root.bar ? root.bar.notchExpandedItems : []
          onPicked: function(item) { root.toggleItem("expanded", root.bar.notchExpandedItems, item) }
        }
      }

      // --- size and shape --------------------------------------------------------

      PanelSeparator { width: parent.width }
      PanelSectionHeader { text: "Size and shape"; fontFamily: root.fontFamily; width: parent.width }

      NumberRow { label: "Width at rest"; key: "compactWidth"; value: root.bar ? root.bar.notchCompactWidth : 180; from: 100; to: 600; stepSize: 10 }
      NumberRow { label: "Height at rest"; key: "compactHeight"; value: root.bar ? root.bar.notchCompactHeight : 32; from: 26; to: 60; stepSize: 2 }
      NumberRow { label: "Bottom corners at rest"; key: "bottomRadius"; value: root.bar ? root.bar.notchBottomRadius : 10; from: 0; to: 24; stepSize: 1 }
      NumberRow { label: "Bottom corners when open"; key: "expandedBottomRadius"; value: root.bar ? root.bar.notchExpandedBottomRadius : 18; from: 0; to: 34; stepSize: 1 }
      NumberRow { label: "Edge fillets"; key: "filletRadius"; value: root.bar ? root.bar.notchFilletRadius : 10; from: 0; to: 24; stepSize: 1 }

      // --- battery -------------------------------------------------------------

      PanelSeparator { width: parent.width }
      PanelSectionHeader { text: "Battery"; fontFamily: root.fontFamily; width: parent.width }

      SettingRow {
        label: "Glow"
        ToggleSwitch {
          checked: root.bar ? root.bar.notchBatteryGlow : true
          onToggled: root.set("batteryGlow", !checked)
        }
      }

      SettingRow {
        label: "While charging"
        ButtonGroup {
          options: [{ value: "always", label: "Glow" }, { value: "plug", label: "Plug-in only" }]
          value: root.bar ? root.bar.notchChargingGlow : "always"
          fontFamily: root.fontFamily
          onChanged: function(value) { root.set("chargingGlow", value) }
        }
      }

      SettingRow {
        label: "Peek on plug-in and low battery"
        ToggleSwitch {
          checked: root.bar ? root.bar.notchBatteryPeek : true
          onToggled: root.set("batteryPeek", !checked)
        }
      }

      NumberRow { label: "Low below %"; key: "lowBattery"; value: root.bar ? root.bar.notchLowBattery : 20; from: 5; to: 60; stepSize: 5 }
      NumberRow { label: "Critical below %"; key: "criticalBattery"; value: root.bar ? root.bar.notchCriticalBattery : 10; from: 1; to: 40; stepSize: 1 }

      SettingRow {
        label: "Preview"
        ButtonGroup {
          readonly property string current: !root.bar || !root.bar.batterySimulated ? "real"
            : root.bar.batterySimulatedState === "charging" ? "charging"
            : root.bar.batterySimulatedPercent <= root.bar.notchCriticalBattery ? "critical" : "low"
          options: [{ value: "real", label: "Off" }, { value: "charging", label: "Charging" },
                    { value: "low", label: "Low" }, { value: "critical", label: "Critical" }]
          value: current
          fontFamily: root.fontFamily
          onChanged: function(value) {
            var b = root.bar
            if (!b) return
            if (value === "real") { b.batterySimulatedState = ""; b.batterySimulatedPercent = -1; return }
            b.batterySimulatedPercent = value === "charging" ? 64
              : value === "critical" ? Math.max(1, b.notchCriticalBattery - 2)
              : Math.max(b.notchCriticalBattery + 1, b.notchLowBattery - 2)
            b.batterySimulatedState = value === "charging" ? "charging" : "discharging"
          }
        }
      }

      PanelSeparator { width: parent.width }

      Item {
        width: parent.width
        height: resetButton.implicitHeight + Style.space(8)
        Button {
          id: resetButton
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          text: "Reset to defaults"
          bordered: true
          fontFamily: root.fontFamily
          onClicked: root.resetAll()
        }
      }
    }
  }

  // Leaving the menu stops any battery preview it started.
  onOpenChanged: if (!open && bar && bar.batterySimulated) { bar.batterySimulatedState = ""; bar.batterySimulatedPercent = -1 }

  component SettingRow: Item {
    id: row
    property string label: ""
    default property alias control: slot.data
    width: parent ? parent.width : 0
    height: Math.max(root.rowHeight, slot.childrenRect.height + Style.space(6))

    Text {
      anchors.left: parent.left
      anchors.right: slot.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: row.label
      elide: Text.ElideRight
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Item {
      id: slot
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: childrenRect.width
      height: childrenRect.height
    }
  }

  component NumberRow: SettingRow {
    id: numberRow
    property string key: ""
    property int value: 0
    property int from: 0
    property int to: 100
    property int stepSize: 1
    NumberField {
      value: numberRow.value
      from: numberRow.from
      to: numberRow.to
      stepSize: numberRow.stepSize
      fontFamily: root.fontFamily
      onModified: function(value) { root.set(numberRow.key, value) }
    }
  }

  component ItemChips: Row {
    id: chips
    property var selected: []
    signal picked(string item)
    spacing: Style.space(4)
    Repeater {
      model: [{ value: "clock", label: "Time" }, { value: "date", label: "Date" },
              { value: "media", label: "Media" }, { value: "battery", label: "Battery" }]
      Button {
        required property var modelData
        text: modelData.label
        selected: chips.selected.indexOf(modelData.value) !== -1
        bordered: true
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.space(7)
        onClicked: chips.picked(modelData.value)
      }
    }
  }
}
