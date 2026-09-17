import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "keys.js" as KeyCombo

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

  // Drawn on the notch, so colours come from the notch: text that reads on the
  // notch colour whatever the theme (see Bar.qml, "colours on the notch").
  readonly property color foreground: bar ? bar.notchForeground : Color.foreground
  readonly property color accent: bar ? bar.notchAccent : Color.accent
  readonly property color surface: bar ? bar.notchColor : Color.background
  readonly property color dim: bar ? bar.notchSecondaryText : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.6)
  // How far the glow reaches now, in px (for the preview's hint).
  property real glowReach: 32
  // The notch's radius for a control this tall (DESIGN-PHILOSOPHY.md, 5).
  function radiusFor(height) { return bar ? bar.radiusFor(height) : Math.max(0, Math.min(10, height / 2)) }
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
  readonly property var menuTriggers: [
    { value: "click", label: "Click" }, { value: "doubleClick", label: "Double-click" },
    { value: "longPress", label: "Long press" }, { value: "rightClick", label: "Right-click" },
    { value: "longRightClick", label: "Long right-click" }, { value: "middleClick", label: "Middle-click" }
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
      foreground: root.foreground
      accent: root.accent
      radius: root.radiusFor(Math.min(width, height))
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

      // Sections fold; "What it shows" starts open. Long plugin lists fold
      // inside them, with a summary of what is picked.

      Section {
        title: "What it shows"
        open: true

        SettingRow {
          label: "At rest"
          ItemChips {
            selected: root.bar ? root.bar.notchCompactItems : []
            onPicked: function(item) { root.toggleItem("compact", root.bar.notchCompactItems, item) }
          }
        }

        SettingRow {
          label: "On hover"
          ItemChips {
            selected: root.bar ? root.bar.notchHoverItems : []
            onPicked: function(item) { root.toggleItem("hoverItems", root.bar.notchHoverItems, item) }
          }
        }

        PluginPicker {
          label: "Plugins on hover"
          key: "hoverPlugins"
          selected: root.bar ? root.bar.notchHoverPlugins : []
        }

        Text {
          visible: root.bar && root.bar.opensWith("hover")
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Hover opens the notch (see Behaviour), so these are not shown."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          bottomPadding: Style.space(4)
        }

        ViewRow {
          label: "When open (click, keybind, …)"
          actionKey: "openAction"; pluginKey: "openPlugin"
          action: root.bar ? root.bar.notchOpenAction : "widgets"
          plugin: root.bar ? root.bar.notchOpenPlugin : ""
        }

        PluginPicker {
          label: "Hide from the open notch"
          key: "hiddenPlugins"
          selected: root.bar ? root.bar.notchHiddenPlugins : []
          // A plugin declaring hideable: false can't be hidden.
          locked: root.bar ? root.bar.notchPlugins.list.filter(function(p) { return p.hideable === false }).map(function(p) { return p.id }) : []
        }

        SettingRow {
          label: "Also in the widget row"
          ItemChips {
            selected: root.bar ? root.bar.notchExpandedItems : []
            onPicked: function(item) { root.toggleItem("expanded", root.bar.notchExpandedItems, item) }
          }
        }
      }

      Section {
        title: "Behaviour"

        StackedRow {
          label: "Open the notch with"
          ChipFlow {
            options: root.openTriggers
            selected: root.bar ? root.bar.notchOpenWith : []
            taken: root.bar ? root.bar.notchSettingsWith.concat(root.bar.notchMenuWith) : []
            onPicked: function(value) { root.toggleTrigger("openWith", root.bar.notchOpenWith, value, false) }
          }
        }

        KeyRow { label: "Keybind for the notch"; key: "openKey"; current: root.bar ? root.bar.notchOpenKey : "" }

        StackedRow {
          label: "Open settings with"
          ChipFlow {
            options: root.settingsTriggers
            selected: root.bar ? root.bar.notchSettingsWith : []
            taken: root.bar ? root.bar.notchOpenWith.concat(root.bar.notchMenuWith) : []
            onPicked: function(value) { root.toggleTrigger("settingsWith", root.bar.notchSettingsWith, value, true) }
          }
        }

        KeyRow { label: "Keybind for settings"; key: "settingsKey"; current: root.bar ? root.bar.notchSettingsKey : "" }

        StackedRow {
          label: "Open the Omarchy menu with"
          ChipFlow {
            options: root.menuTriggers
            selected: root.bar ? root.bar.notchMenuWith : []
            taken: root.bar ? root.bar.notchOpenWith.concat(root.bar.notchSettingsWith) : []
            onPicked: function(value) { root.toggleTrigger("menuWith", root.bar.notchMenuWith, value, false) }
          }
        }

        KeyRow { label: "Keybind for the menu"; key: "menuKey"; current: root.bar ? root.bar.notchMenuKey : "" }

        SettingRow {
          label: "Hide until the pointer reaches for it"
          Switch {
            checked: root.bar ? root.bar.notchAutoHide : false
            onToggled: root.set("autoHide", !checked)
          }
        }

        KeyRow { label: "Keybind for auto-hide"; key: "autoHideKey"; current: root.bar ? root.bar.notchAutoHideKey : "" }

        SettingRow {
          label: "Windows reach the top edge"
          Switch {
            checked: root.bar ? root.bar.notchWindowsToTop : false
            onToggled: root.set("windowsToTop", !checked)
          }
        }

        Text {
          visible: root.bar && root.bar.notchAutoHide && !root.bar.notchWindowsToTopSet
          width: parent.width
          wrapMode: Text.WordWrap
          text: "On while the notch auto-hides. Switch it off to keep windows below the notch."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          bottomPadding: Style.space(4)
        }

        SettingRow {
          label: "Peek on a new track"
          Switch {
            checked: root.bar ? root.bar.notchPeekOnTrackChange : true
            onToggled: root.set("peekOnTrackChange", !checked)
          }
        }
      }

      Section {
        title: "Size and shape"

        NumberRow { label: "Width at rest"; key: "compactWidth"; value: root.bar ? root.bar.notchCompactWidth : 180; from: 100; to: 600; stepSize: 10 }
        NumberRow { label: "Height at rest"; key: "compactHeight"; value: root.bar ? root.bar.notchCompactHeight : 32; from: 26; to: 60; stepSize: 2 }
        NumberRow { label: "Bottom corners"; key: "bottomRadius"; value: root.bar ? root.bar.notchBottomRadius : 10; from: 0; to: 24; stepSize: 1 }
        NumberRow { label: "Edge fillets"; key: "filletRadius"; value: root.bar ? root.bar.notchFilletRadius : 10; from: 0; to: 24; stepSize: 1 }
      }

      Section {
        title: "Battery"

        SettingRow {
          label: "Charging glow"
          Switch {
            checked: root.bar ? root.bar.notchBatteryGlow : true
            onToggled: root.set("batteryGlow", !checked)
          }
        }

        SettingRow {
          label: "Glow style"
          Choice {
            options: [{ value: "outline", label: "Outline" }, { value: "bottom", label: "Bottom" }]
            value: root.bar ? root.bar.notchGlowStyle : "outline"
            fontFamily: root.fontFamily
            onChanged: function(value) { root.set("glowStyle", value) }
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
              minimum: 0
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
              readonly property real shownScale: glowScaleSlider.dragging ? glowScaleRow.liveScale : (root.bar ? root.bar.notchGlowScale : 1)
              text: shownScale <= 0 ? "off" : shownScale.toFixed(2) + "×"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        SettingRow {
          label: "Peek on plug-in and low battery"
          Switch {
            checked: root.bar ? root.bar.notchBatteryPeek : true
            onToggled: root.set("batteryPeek", !checked)
          }
        }

        NumberRow { label: "Green when charging above %"; key: "greenAbove"; value: root.bar ? root.bar.notchGreenAbove : 100; from: 0; to: 100; stepSize: 5 }
        NumberRow { label: "Low below %"; key: "lowBattery"; value: root.bar ? root.bar.notchLowBattery : 20; from: 5; to: 60; stepSize: 5 }
        NumberRow { label: "Critical below %"; key: "criticalBattery"; value: root.bar ? root.bar.notchCriticalBattery : 10; from: 1; to: 40; stepSize: 1 }

        SettingRow {
          label: "Preview"
          Choice {
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

        // The preview shows the real glow, so at a tiny glow size there is
        // nothing to see: say so rather than look broken.
        Text {
          visible: text !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          text: !root.bar ? ""
            : !root.bar.notchBatteryGlow ? "The battery glow is switched off, so the preview has nothing to show."
            : root.bar.notchGlowScale <= 0 ? "Glow size is off, so the preview has nothing to show. Raise Glow size to see it."
            : root.glowReach < 4 ? "Glow size " + root.bar.notchGlowScale.toFixed(2) + "× reaches only " + root.glowReach.toFixed(1) + " px, too small to see. Raise Glow size to see the preview."
            : root.bar.batterySimulated ? "Previewing: while the settings are open the glow sits under the panel's bottom edge. It stops when the settings close."
            : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          bottomPadding: Style.space(4)
        }
      }

      PanelSeparator { width: parent.width; foreground: root.foreground }

      Item {
        width: parent.width
        height: resetButton.implicitHeight + Style.space(8)
        Button {
          id: resetButton
          foreground: root.foreground
          accent: root.accent
          radius: root.radiusFor(Math.min(width, height))
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
        foreground: root.foreground
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
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

  // A settings section whose title folds and unfolds it. Folded state lasts
  // while the shell runs (it is not saved).
  component Section: Column {
    id: section
    property string title: ""
    property bool open: false
    default property alias content: sectionBody.data
    width: parent ? parent.width : 0

    Item {
      width: parent.width
      height: Style.space(30)

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: (section.open ? "▾  " : "▸  ") + section.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: section.open = !section.open
      }
    }

    Column {
      id: sectionBody
      visible: section.open
      width: parent.width
      spacing: Style.space(2)
      bottomPadding: Style.space(8)
    }

    PanelSeparator { width: parent.width; foreground: root.foreground }
  }

  // A plugin list folded to one line: the label, what is picked, and a
  // chevron; unfolded, a chip per widget in the bar layout. Many can be
  // picked, or with `single` just one. Saves `key` on every pick.
  component PluginPicker: Column {
    id: picker
    property string label: ""
    property string key: ""
    property var selected: []
    property bool single: false
    property bool open: false
    // Ids shown but not pickable.
    property var locked: []
    readonly property var choices: root.bar ? root.bar.layoutPluginChoices() : []
    readonly property string summary: {
      var names = []
      for (var i = 0; i < choices.length; i++)
        if (selected.indexOf(choices[i].value) !== -1) names.push(choices[i].label)
      if (names.length === 0) return "none"
      return names.length <= 2 ? names.join(", ") : names.length + " picked"
    }
    width: parent ? parent.width : 0

    Item {
      width: parent.width
      height: root.rowHeight

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: picker.label
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * 0.55
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        text: picker.summary + (picker.open ? "  ▾" : "  ▸")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: picker.open = !picker.open
      }
    }

    ChipFlow {
      visible: picker.open
      options: picker.choices
      selected: picker.selected
      taken: picker.locked
      bottomPadding: Style.space(6)
      onPicked: function(value) {
        if (picker.single) { root.set(picker.key, value); return }
        var next = picker.selected.slice()
        var i = next.indexOf(value)
        if (i === -1) next.push(value)
        else next.splice(i, 1)
        root.set(picker.key, next)
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
                  { value: "settings", label: "Settings" }, { value: "menu", label: "Menu" }].concat(viewRow.allowNothing ? [{ value: "none", label: "Nothing" }] : [])
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

    PluginPicker {
      visible: viewRow.action === "plugin"
      label: "Which plugin"
      key: viewRow.pluginKey
      single: true
      selected: viewRow.plugin ? [viewRow.plugin] : []
    }
  }

  // A Hyprland key combination, applied when typing finishes (Enter or
  // leaving the field). Empty removes the keybind.
  // A keybind: the current combination, a Record button that listens for
  // the next key press (Escape cancels), and ✕ to remove it. Saved on record.
  component KeyRow: SettingRow {
    id: keyRow
    property string key: ""
    property string current: ""
    property bool recording: false
    property string hint: ""

    // Every notch keybind, so one combination can't be recorded twice.
    function usedBy(combo) {
      if (!root.bar) return ""
      var others = { openKey: root.bar.notchOpenKey, settingsKey: root.bar.notchSettingsKey, autoHideKey: root.bar.notchAutoHideKey, menuKey: root.bar.notchMenuKey }
      var labels = { openKey: "the notch", settingsKey: "settings", autoHideKey: "auto-hide", menuKey: "the menu" }
      for (var k in others) if (k !== keyRow.key && others[k] === combo) return labels[k]
      return ""
    }

    function stop() {
      recording = false
      root.forceActiveFocus()
    }

    Row {
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: keyRow.recording ? (keyRow.hint || "press keys…") : (keyRow.hint || (keyRow.current || "none"))
        color: keyRow.recording || keyRow.hint ? root.dim : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Button {
        foreground: root.foreground
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
        text: keyRow.recording ? "Cancel" : "Record"
        bordered: true
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.space(7)
        onClicked: {
          keyRow.hint = ""
          if (keyRow.recording) { keyRow.stop(); return }
          keyRow.recording = true
          catcher.forceActiveFocus()
        }
      }

      Button {
        foreground: root.foreground
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
        visible: keyRow.current !== "" && !keyRow.recording
        text: "✕"
        bordered: true
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.space(6)
        onClicked: { keyRow.hint = ""; root.set(keyRow.key, "") }
      }
    }

    Item {
      id: catcher
      focus: keyRow.recording
      Keys.onPressed: function(event) {
        if (!keyRow.recording) return
        event.accepted = true
        if (event.key === KeyCombo.ESCAPE) { keyRow.hint = ""; keyRow.stop(); return }
        var result = KeyCombo.combo(event.key, event.modifiers)
        if (result.waiting) return
        if (!result.combo) { keyRow.hint = result.reason; return }
        var clash = keyRow.usedBy(result.combo)
        if (clash) { keyRow.hint = result.combo + " is used by " + clash; return }
        keyRow.hint = ""
        root.set(keyRow.key, result.combo)
        keyRow.stop()
      }
      onActiveFocusChanged: if (!activeFocus && keyRow.recording) keyRow.recording = false
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
      id: numberField
      foreground: root.foreground
      accent: root.accent
      // NumberField takes its corner from the theme; give its box the notch's.
      // Its box and its up/down buttons take their corners from the theme; give
      // them the notch's.
      Component.onCompleted: {
        if (!field) return
        var parts = [field.background, field.up ? field.up.indicator : null, field.down ? field.down.indicator : null]
        parts.forEach(function(part) {
          if (part && part.radius !== undefined)
            part.radius = Qt.binding(function() { return root.radiusFor(Math.min(part.height, part.width)) })
        })
      }
      value: numberRow.value
      from: numberRow.from
      to: numberRow.to
      stepSize: numberRow.stepSize
      fontFamily: root.fontFamily
      onModified: function(value) { root.set(numberRow.key, value) }
    }
  }

  // Omarchy's ButtonGroup, with the notch's colours and radius: one of N.
  component Choice: Row {
    id: choice
    property var options: []
    property string value: ""
    property string fontFamily: root.fontFamily
    signal changed(string value)
    spacing: Style.spacing.md
    Repeater {
      model: choice.options
      Button {
        required property var modelData
        text: modelData.label
        selected: modelData.value === choice.value
        bordered: true
        foreground: root.foreground
        background: root.surface
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
        fontFamily: choice.fontFamily
        onClicked: choice.changed(modelData.value)
      }
    }
  }

  // Omarchy's ToggleSwitch, with the notch's colours and radius. `toggled`
  // fires before `checked` changes, as ToggleSwitch's does.
  component Switch: Item {
    id: toggle
    property bool checked: false
    signal toggled()
    readonly property int trackHeight: Math.max(22, Math.round(Style.spacing.controlHeight * 0.55))
    readonly property int trackWidth: Math.round(trackHeight * 1.9)
    readonly property int knobSize: Math.max(6, Math.round(trackHeight * 0.72))
    readonly property int knobInset: Math.max(1, Math.round((trackHeight - knobSize) / 2))
    implicitWidth: trackWidth
    implicitHeight: trackHeight

    BorderSurface {
      id: track
      anchors.fill: parent
      radius: root.radiusFor(Math.min(width, height))
      color: toggle.checked ? Style.selectedFillFor(root.foreground, root.accent) : Style.normalFillFor(root.foreground, root.accent)
      borderSpec: Border.controlSpec(toggle.checked ? "selected" : (switchMouse.containsMouse ? "hover-cursor" : "normal"), root.foreground, root.accent)
      Behavior on color { ColorAnimation { duration: 120 } }

      Rectangle {
        width: toggle.knobSize
        height: toggle.knobSize
        radius: root.radiusFor(Math.min(width, height))
        x: toggle.checked ? track.width - width - toggle.knobInset : toggle.knobInset
        anchors.verticalCenter: parent.verticalCenter
        color: toggle.checked ? Style.selectedStateColor(root.foreground, root.accent) : Qt.darker(root.foreground, 1.25)
        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 120 } }
      }
    }

    MouseArea {
      id: switchMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: toggle.toggled()
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
        foreground: root.foreground
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
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
