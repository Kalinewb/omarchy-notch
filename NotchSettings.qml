import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// The notch's settings, drawn inside the notch itself: opening them grows the
// notch -- the same surface, top edge on the screen edge -- into this panel.
// Opened by a long right-click, by the hover action "Settings", or over IPC;
// closed by clicking outside, Escape, or the ✕.
//
// Every control reads the live value from the bar and writes straight to
// `bar.notch` in shell.json through `bar.setNotchSetting`, so a change shows
// on the notch at once and survives a restart. The battery preview is the one
// thing that is not saved: it only simulates a battery state while chosen.
Item {
  id: root

  // The notch's Bar.qml root.
  property var bar: null
  // How tall the notch may grow for this panel; past that it scrolls.
  property real maxHeight: 600
  // The notch's resting height: the header sits on that row, where the
  // resting notch's own content sits.
  property real headerHeight: 32
  signal closeRequested()

  readonly property real padding: Style.space(16)
  implicitWidth: Style.space(400)
  implicitHeight: Math.min(maxHeight, headerHeight + column.implicitHeight + padding)

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

  readonly property var openTriggers: [
    { value: "hover", label: "Hover" }, { value: "click", label: "Click" },
    { value: "doubleClick", label: "Double-click" }, { value: "longPress", label: "Long press" },
    { value: "rightClick", label: "Right-click" }, { value: "middleClick", label: "Middle-click" },
    { value: "scroll", label: "Scroll" }
  ]
  readonly property var settingsTriggers: [
    { value: "longRightClick", label: "Long right-click" }, { value: "rightClick", label: "Right-click" },
    { value: "doubleClick", label: "Double-click" }, { value: "longPress", label: "Long press" },
    { value: "middleClick", label: "Middle-click" }
  ]

  // Add or remove one trigger. The settings keep at least one way in: their
  // last trigger cannot be removed unless a keybind opens them.
  function toggleTrigger(key, current, trigger, isSettings) {
    var next = current.slice()
    var i = next.indexOf(trigger)
    if (i === -1) next.push(trigger)
    else {
      if (isSettings && next.length === 1 && !(bar && bar.notchSettingsKey)) return
      next.splice(i, 1)
    }
    set(key, next)
  }

  function resetAll() {
    if (!bar || !bar.shell || typeof bar.shell.mutateShellConfig !== "function") return
    bar.batterySimulatedState = ""
    bar.shell.mutateShellConfig(function(config) {
      if (Util.isPlainObject(config.bar)) delete config.bar.notch
    })
  }

  focus: true
  Keys.onEscapePressed: root.closeRequested()

  // Header, on the resting notch's row.
  Item {
    x: root.padding
    width: parent.width - 2 * root.padding
    height: root.headerHeight

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "Notch"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Button {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: "✕"
      fontFamily: root.fontFamily
      horizontalPadding: Style.space(8)
      onClicked: root.closeRequested()
    }
  }

  Flickable {
    x: root.padding
    y: root.headerHeight
    width: parent.width - 2 * root.padding
    height: parent.height - root.headerHeight - root.padding
    contentWidth: width
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: column
      width: parent.width
      spacing: Style.space(2)

      // --- what it shows ---------------------------------------------------------

      PanelSectionHeader { text: "What it shows"; fontFamily: root.fontFamily; width: parent.width }

      SettingRow {
        label: "At rest"
        ItemChips {
          selected: root.bar ? root.bar.notchCompactItems : []
          onPicked: function(item) { root.toggleItem("compact", root.bar.notchCompactItems, item) }
        }
      }

      ViewRow {
        label: "On hover"
        // What hovering shows when hover is not one of the ways to open the
        // notch; when it is, hovering opens the notch instead, so say that.
        allowNothing: true
        note: root.bar && root.bar.opensWith("hover") ? "Hover opens the notch (see Behaviour), so this is not used." : ""
        actionKey: "hoverAction"; pluginKey: "hoverPlugin"
        action: root.bar ? root.bar.notchHoverAction : "widgets"
        plugin: root.bar ? root.bar.notchHoverPlugin : ""
      }

      ViewRow {
        label: "When open (click, keybind, …)"
        actionKey: "openAction"; pluginKey: "openPlugin"
        action: root.bar ? root.bar.notchOpenAction : "widgets"
        plugin: root.bar ? root.bar.notchOpenPlugin : ""
      }

      StackedRow {
        label: "Hide from the open notch"
        ChipFlow {
          options: root.bar ? root.bar.layoutPluginChoices() : []
          selected: root.bar ? root.bar.notchHiddenPlugins : []
          onPicked: function(value) {
            var next = root.bar.notchHiddenPlugins.slice()
            var i = next.indexOf(value)
            if (i === -1) next.push(value)
            else next.splice(i, 1)
            root.set("hiddenPlugins", next)
          }
        }
      }

      SettingRow {
        label: "Also in the widget row"
        ItemChips {
          selected: root.bar ? root.bar.notchExpandedItems : []
          onPicked: function(item) { root.toggleItem("expanded", root.bar.notchExpandedItems, item) }
        }
      }

      PanelSeparator { width: parent.width }

      // --- behaviour ---------------------------------------------------------

      PanelSectionHeader { text: "Behaviour"; fontFamily: root.fontFamily; width: parent.width }

      StackedRow {
        label: "Open the notch with"
        ChipFlow {
          options: root.openTriggers
          selected: root.bar ? root.bar.notchOpenWith : []
          taken: root.bar ? root.bar.notchSettingsWith : []
          onPicked: function(value) { root.toggleTrigger("openWith", root.bar.notchOpenWith, value, false) }
        }
      }

      KeyRow { label: "Keybind for the notch"; key: "openKey"; current: root.bar ? root.bar.notchOpenKey : "" }

      StackedRow {
        label: "Open settings with"
        ChipFlow {
          options: root.settingsTriggers
          selected: root.bar ? root.bar.notchSettingsWith : []
          taken: root.bar ? root.bar.notchOpenWith : []
          onPicked: function(value) { root.toggleTrigger("settingsWith", root.bar.notchSettingsWith, value, true) }
        }
      }

      KeyRow { label: "Keybind for settings"; key: "settingsKey"; current: root.bar ? root.bar.notchSettingsKey : "" }

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

      // --- size and shape --------------------------------------------------------

      PanelSeparator { width: parent.width }
      PanelSectionHeader { text: "Size and shape"; fontFamily: root.fontFamily; width: parent.width }

      NumberRow { label: "Width at rest"; key: "compactWidth"; value: root.bar ? root.bar.notchCompactWidth : 180; from: 100; to: 600; stepSize: 10 }
      NumberRow { label: "Height at rest"; key: "compactHeight"; value: root.bar ? root.bar.notchCompactHeight : 32; from: 26; to: 60; stepSize: 2 }
      NumberRow { label: "Bottom corners"; key: "bottomRadius"; value: root.bar ? root.bar.notchBottomRadius : 10; from: 0; to: 24; stepSize: 1 }
      NumberRow { label: "Edge fillets"; key: "filletRadius"; value: root.bar ? root.bar.notchFilletRadius : 10; from: 0; to: 24; stepSize: 1 }

      // --- battery -------------------------------------------------------------

      PanelSeparator { width: parent.width }
      PanelSectionHeader { text: "Battery"; fontFamily: root.fontFamily; width: parent.width }

      SettingRow {
        label: "Charging glow"
        ToggleSwitch {
          checked: root.bar ? root.bar.notchBatteryGlow : true
          onToggled: root.set("batteryGlow", !checked)
        }
      }

      SettingRow {
        id: glowScaleRow
        label: "Glow size"
        // Relative to the resting notch's size (1.0 reaches 32 px on the
        // default 180 × 32 notch, further on a bigger one; at most 80 px). The slider shows its value while it
        // moves and saves once on release.
        property real liveScale: root.bar ? root.bar.notchGlowScale : 1
        Row {
          spacing: Style.space(8)
          PanelSlider {
            id: glowScaleSlider
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(160)
            height: Style.space(24)
            bar: root.bar
            minimum: 0.25
            maximum: 2.5
            step: 0.05
            value: root.bar ? root.bar.notchGlowScale : 1
            onMoved: function(value) { glowScaleRow.liveScale = value }
            onReleased: function(value) { root.set("glowScale", Math.round(value * 100) / 100) }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(44)
            horizontalAlignment: Text.AlignRight
            text: (glowScaleSlider.dragging ? glowScaleRow.liveScale : (root.bar ? root.bar.notchGlowScale : 1)).toFixed(2) + "×"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
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
            : root.bar.batterySimulatedState
          options: [{ value: "real", label: "Off" }, { value: "charging", label: "Charging" },
                    { value: "full", label: "Full" }, { value: "discharging", label: "Low" }]
          value: current
          fontFamily: root.fontFamily
          onChanged: function(value) {
            var b = root.bar
            if (!b) return
            if (value === "real") { b.batterySimulatedState = ""; b.batterySimulatedPercent = -1; return }
            b.batterySimulatedPercent = value === "charging" ? 64 : value === "full" ? 100 : Math.max(1, b.notchLowBattery - 2)
            b.batterySimulatedState = value
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

  // A label on its own line with its control below, for controls too wide
  // to share a line.
  component StackedRow: Column {
    id: stacked
    property string label: ""
    default property alias control: stackedSlot.data
    width: parent ? parent.width : 0
    spacing: Style.space(4)
    topPadding: Style.space(6)
    bottomPadding: Style.space(6)

    Text {
      text: stacked.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Item {
      id: stackedSlot
      width: parent.width
      height: childrenRect.height
    }
  }

  // Chips that wrap onto more lines as needed; `selected` holds the values
  // shown as chosen.
  component ChipFlow: Flow {
    id: flow
    property var options: []
    property var selected: []
    // Values another list already uses: shown, but not selectable.
    property var taken: []
    signal picked(string value)
    width: parent ? parent.width : 0
    spacing: Style.space(4)
    Repeater {
      model: flow.options
      Button {
        required property var modelData
        text: modelData.label
        selected: flow.selected.indexOf(modelData.value) !== -1
        enabled: flow.taken.indexOf(modelData.value) === -1
        opacity: enabled ? 1 : 0.35
        bordered: true
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.space(7)
        onClicked: flow.picked(modelData.value)
      }
    }
  }

  // What a way of opening the notch shows, and for "A plugin", which one.
  component ViewRow: Column {
    id: viewRow
    property string label: ""
    property string actionKey: ""
    property string pluginKey: ""
    property string action: "widgets"
    property string plugin: ""
    property bool allowNothing: false
    property string note: ""
    width: parent ? parent.width : 0

    function pick(key, value) { root.set(key, value) }

    StackedRow {
      label: viewRow.label
      ChipFlow {
        options: [{ value: "widgets", label: "Widgets" }, { value: "clock", label: "Clock" },
                  { value: "battery", label: "Battery" }, { value: "plugin", label: "A plugin" },
                  { value: "settings", label: "Settings" }].concat(viewRow.allowNothing ? [{ value: "none", label: "Nothing" }] : [])
        selected: [viewRow.action]
        onPicked: function(value) { viewRow.pick(viewRow.actionKey, value) }
      }
    }

    Text {
      visible: viewRow.note !== ""
      text: viewRow.note
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      bottomPadding: Style.space(4)
    }

    StackedRow {
      visible: viewRow.action === "plugin"
      label: "Which plugin"
      ChipFlow {
        options: root.bar ? root.bar.layoutPluginChoices() : []
        selected: [viewRow.plugin]
        onPicked: function(value) { viewRow.pick(viewRow.pluginKey, value) }
      }
    }
  }

  // A Hyprland key combination, applied when typing finishes (Enter or
  // leaving the field). Empty removes the keybind.
  component KeyRow: SettingRow {
    id: keyRow
    property string key: ""
    property string current: ""
    Row {
      spacing: Style.space(6)
      Text {
        id: keyHint
        anchors.verticalCenter: parent.verticalCenter
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      TextField {
        id: keyField
        width: Style.space(150)
        text: keyRow.current
        placeholderText: "e.g. SUPER + N"
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        onEditingFinished: {
          var clean = root.bar ? root.bar.cleanKey(text) : ""
          if (text.trim() !== "" && clean === "") { keyHint.text = "not a key"; return }
          keyHint.text = ""
          if (clean !== keyRow.current) root.set(keyRow.key, clean)
          text = clean
        }
      }
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
