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
  signal setupRequested()

  readonly property real padding: Style.space(16)
  implicitWidth: Style.space(400)
  implicitHeight: Math.min(maxHeight, headerHeight + column.implicitHeight + padding)

  // Drawn on the notch, so colours come from the notch: text that reads on the
  // notch colour whatever the theme (see Bar.qml, "colours on the notch").
  readonly property color foreground: bar ? bar.notchForeground : "#ffffff"
  readonly property color accent: bar ? bar.notchAccent : "#ffffff"
  readonly property color surface: bar ? bar.notchColor : "#000000"
  readonly property color dim: bar ? bar.notchSecondaryText : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.6)
  // How far the glow reaches now, in px (for the preview's hint).
  property real glowReach: 32
  // What the panel's own controls paint with (dev/colours.sh: no hue).
  readonly property var painted: [replaceMenuSwitch.trackColor, replaceMenuSwitch.knobColor,
                                  setupButton.selectedFill, setupButton.hoverFill, glowScaleSlider.trackColor]

  // Where the notch's own updates stand, in words.
  readonly property string updateStatus: {
    var b = bar
    if (!b) return ""
    if (!b.updatesEnabled) return "This notch doesn't update itself."
    if (b.updateNotice === "updating") return "Updating…"
    var c = b.updateCheckResult || {}
    var version = c.localVersion ? " (" + c.localVersion + ")" : ""
    switch (c.state) {
      case "unchecked": return "Not checked yet" + version + "."
      case "current": return "Up to date" + version + "."
      case "available": return (c.remoteVersion && c.remoteVersion !== c.localVersion ? c.remoteVersion : (c.behind === 1 ? "1 change" : c.behind + " changes")) + " available."
      case "ahead": return "Ahead of GitHub (a development install)."
      case "diverged": return "Differs from GitHub: update by hand."
      case "dirty": return "The plugin folder has local edits: update by hand."
      case "not-git": return "Not a git install, so it can't update itself."
      case "offline": return "Couldn't reach GitHub."
      default: return "Couldn't check for updates."
    }
  }

  // Unfold a section and scroll to it: "updates" (the Plugins page's notch row).
  function revealSection(name) {
    var sections = { shows: showsSection, opening: openingSection, appearance: appearanceSection,
                     battery: batterySection, integrations: integrationsSection, updates: updatesSection }
    var section = sections[name]
    if (!section) return
    section.open = true
    Qt.callLater(function() {
      settingsFlick.contentY = Math.max(0, Math.min(section.y, settingsFlick.contentHeight - settingsFlick.height))
    })
  }

  // Whether Updates is unfolded (dev/plugins.sh).
  readonly property bool updatesSectionOpen: updatesSection.open
  // Whether the notch update's Update button takes a click (dev/plugins.sh).
  readonly property bool updateButtonEnabled: updateNowButton.enabled

  readonly property QtObject sliderPalette: QtObject {
    readonly property color foreground: root.foreground
    readonly property color background: root.surface
  }

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

  // Plugins that declare an integration, whatever the notch made of it.
  readonly property var integrations: bar ? bar.platform.list : []
  // Widgets whose own panel the notch could draw, whether or not they know
  // anything about the notch. Read when the panel shows, not bound: the walk
  // touches every widget's children, and as a binding it re-ran on each
  // widget's creation (a warning per run, 18 MB of log in one startup).
  property var hostable: []
  function refreshHostable() { hostable = bar ? bar.hostableWidgets() : [] }
  // `enabled` follows the host's `shown` exactly, so this is "the panel is
  // being opened" with no dependence on the fade. Component.onCompleted alone
  // caught only what had loaded by the notch's first second.
  onEnabledChanged: if (enabled) refreshHostable()
  Component.onCompleted: refreshHostable()

  // Show this plugin inside the notch, or give it its own UI back. The list of
  // ids that are off is the setting; everything else follows from it.
  function toggleIntegration(id, off) {
    if (!bar) return
    var next = (bar.notchDisabledIntegrations || []).slice()
    var at = next.indexOf(id)
    if (off && at === -1) next.push(id)
    else if (!off && at !== -1) next.splice(at, 1)
    else return
    set("disabledIntegrations", next)
  }

  // Draw this widget's own panel inside the notch, or give it back to its own
  // window. Takes effect on the next click; a panel open right now is released.
  function toggleHostedPanel(id, hosted) {
    Qt.callLater(refreshHostable)
    if (!bar) return
    var next = (bar.notchHostedPanels || []).slice()
    var at = next.indexOf(id)
    if (hosted && at === -1) next.push(id)
    else if (!hosted && at !== -1) next.splice(at, 1)
    else return
    if (!hosted) bar.releaseHostedPanel()
    set("hostedPanels", next)
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

    // Setup, with the number of things that need attention.
    NotchButton {
      id: setupButton
      foreground: root.foreground
      accent: root.accent
      radius: root.radiusFor(Math.min(width, height))
      anchors.right: closeButton.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      visible: !!root.bar && root.bar.setup.enabled
      text: {
        var n = root.bar ? root.bar.setup.issueCount : 0
        return n > 0 ? "Setup · " + n : "Setup"
      }
      fontFamily: root.fontFamily
      horizontalPadding: Style.space(10)
      onClicked: root.setupRequested()
    }

    NotchButton {
      id: closeButton
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
    id: settingsFlick
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
        id: showsSection
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

        // Omarchy's own toast still appears as well: the notch is a second
        // display of the same thing, not a replacement for the daemon.
        SettingRow {
          label: "Omarchy's notifications"
          Switch {
            checked: root.bar ? root.bar.notchNotifications : true
            onToggled: root.set("notifications", !checked)
          }
        }

        SettingRow {
          label: "Also in the widget row"
          ItemChips {
            selected: root.bar ? root.bar.notchExpandedItems : []
            onPicked: function(item) { root.toggleItem("expanded", root.bar.notchExpandedItems, item) }
          }
        }
      }

      // Every row here answers "what makes the notch do a thing"; each
      // gesture is followed by its keybind.
      Section {
        id: openingSection
        title: "How it opens"

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

        // Just the switch. The companion plugin it needs is the notch's
        // business (MenuCompanion.keepInStep); Setup's if that fails.
        SettingRow {
          label: "Replace the Omarchy menu"
          Switch {
            id: replaceMenuSwitch
            checked: root.bar ? root.bar.notchReplaceMenu : false
            onToggled: root.set("replaceMenu", !checked)
          }
        }

        SettingRow {
          label: "Keep the notch open"
          Switch {
            checked: root.bar ? root.bar.notchStayOpen : false
            onToggled: root.set("stayOpen", !checked)
          }
        }

        KeyRow { label: "Keybind to keep it open"; key: "stayOpenKey"; current: root.bar ? root.bar.notchStayOpenKey : "" }

      }

      // The notch's shape, and how it sits on the screen: auto-hide and
      // windows-to-top are about its presence, not about what opens it.
      Section {
        id: appearanceSection
        title: "Appearance"

        NumberRow { label: "Width at rest"; key: "compactWidth"; value: root.bar ? root.bar.notchCompactWidth : 180; from: 100; to: 600; stepSize: 10 }
        NumberRow { label: "Height at rest"; key: "compactHeight"; value: root.bar ? root.bar.notchCompactHeight : 32; from: 26; to: 60; stepSize: 2 }
        NumberRow { label: "Bottom corners"; key: "bottomRadius"; value: root.bar ? root.bar.notchBottomRadius : 10; from: 0; to: 24; stepSize: 1 }
        NumberRow { label: "Edge fillets"; key: "filletRadius"; value: root.bar ? root.bar.notchFilletRadius : 10; from: 0; to: 24; stepSize: 1 }

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
      }

      // The two peeks are one idea -- the notch briefly showing you something
      // -- so they sit together, ahead of the glow they used to be split by.
      Section {
        id: batterySection
        title: "Peeks and battery"
        summary: !root.bar ? "" : !root.bar.notchBatteryGlow ? "Glow off"
          : (root.bar.notchGlowStyle === "bottom" ? "Bottom" : "Outline") + " · " + root.bar.notchGlowScale.toFixed(2) + "× · green above " + root.bar.notchGreenAbove + " %"

        SettingRow {
          label: "Peek on a new track"
          Switch {
            checked: root.bar ? root.bar.notchPeekOnTrackChange : true
            onToggled: root.set("peekOnTrackChange", !checked)
          }
        }

        SettingRow {
          label: "Peek on plug-in and low battery"
          Switch {
            checked: root.bar ? root.bar.notchBatteryPeek : true
            onToggled: root.set("batteryPeek", !checked)
          }
        }

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
              // Omarchy's slider takes its colours off `bar`, and its track off
              // a theme token: hand it the notch's palette instead.
              bar: sliderPalette
              trackColor: Util.alpha(root.foreground, Style.selectedFillAlpha)
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

      // Plugins that draw inside the notch. Hidden until one says it can.
      Section {
        id: integrationsSection
        title: "Integrations"
        visible: root.integrations.length > 0 || root.hostable.length > 0
        onOpenChanged: if (open) root.refreshHostable()

        Repeater {
          model: root.integrations

          SettingRow {
            label: modelData.name || modelData.id
            Row {
              spacing: Style.space(8)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.reasonText
                color: modelData.accepted ? root.dim : root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Switch {
                checked: !modelData.userOff
                onToggled: root.toggleIntegration(modelData.id, !checked)
              }
            }
          }
        }

        // Widgets already in the bar whose own panel the notch can draw. These
        // need nothing from the plugin: the notch takes its panel while it is
        // open and gives it back untouched.
        Repeater {
          model: root.hostable

          SettingRow {
            label: modelData.name
            Row {
              spacing: Style.space(8)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.hosted ? "Opens in the notch" : "Opens in its own window"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Switch {
                checked: modelData.hosted
                onToggled: root.toggleHostedPanel(modelData.id, !checked)
              }
            }
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "A plugin that integrates opens its own panel inside the notch, on the notch's colour and motion. Switching one off gives that plugin its own window back at once."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          bottomPadding: Style.space(4)
        }
      }

      Section {
        id: updatesSection
        title: "Updates"

        SettingRow {
          label: "Check for updates"
          Switch {
            checked: root.bar ? root.bar.notchUpdateCheck : true
            onToggled: root.set("updateCheck", !checked)
          }
        }

        SettingRow {
          label: root.updateStatus
          Row {
            spacing: Style.space(6)
            NotchButton {
              id: updateNowButton
              visible: root.bar && root.bar.updateNotice === "" && root.bar.updateCheckResult && root.bar.updateCheckResult.state === "available"
              // Not while a plugin job runs: both reload every plugin.
              enabled: !!root.bar && !root.bar.pluginJobRunning
              opacity: enabled ? 1 : 0.35
              text: "Update"
              bordered: true
              selected: true
              foreground: root.foreground
              accent: root.accent
              radius: root.radiusFor(Math.min(width, height))
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(7)
              onClicked: root.bar.startUpdate()
            }
            NotchButton {
              text: root.bar && root.bar.updateCheckRunning ? "Checking…" : "Check now"
              enabled: root.bar && root.bar.updatesEnabled && !root.bar.updateCheckRunning
              bordered: true
              foreground: root.foreground
              accent: root.accent
              radius: root.radiusFor(Math.min(width, height))
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(7)
              onClicked: root.bar.checkForUpdates()
            }
          }
        }
      }

      PanelSeparator { width: parent.width; foreground: root.foreground }

      Item {
        width: parent.width
        height: resetButton.implicitHeight + Style.space(8)
        NotchButton {
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
      NotchButton {
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
    // One line of the current state, shown on the fold so it isn't a dead end.
    property string summary: ""
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

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: !section.open && section.summary !== ""
        text: section.summary
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
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
      var others = { openKey: root.bar.notchOpenKey, settingsKey: root.bar.notchSettingsKey, autoHideKey: root.bar.notchAutoHideKey, menuKey: root.bar.notchMenuKey, stayOpenKey: root.bar.notchStayOpenKey }
      var labels = { openKey: "the notch", settingsKey: "settings", autoHideKey: "auto-hide", menuKey: "the menu", stayOpenKey: "keep open" }
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

      NotchButton {
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

      NotchButton {
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
    NotchNumberField {
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
      NotchButton {
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

    // Fills and outline are the text colour at the theme's alpha, never a
    // colour the theme pinned in a style token (NotchButton.qml).
    readonly property string borderState: toggle.checked ? "selected" : (switchMouse.containsMouse ? "hover-cursor" : "normal")
    readonly property color trackColor: track.color
    readonly property color knobColor: knob.color

    BorderSurface {
      id: track
      anchors.fill: parent
      radius: root.radiusFor(Math.min(width, height))
      color: Util.alpha(root.foreground, toggle.checked ? Style.selectedFillAlpha : Style.normalFillAlpha)
      borderSpec: ({ color: Util.alpha(root.foreground, toggle.checked ? Style.selectedBorderAlpha : (switchMouse.containsMouse ? Style.hoverBorderAlpha : Style.normalBorderAlpha)),
                     widths: Border.controlSpec(toggle.borderState, root.foreground, root.foreground).widths,
                     gradient: { colors: [], angle: 0, enabled: false } })
      Behavior on color { ColorAnimation { duration: 120 } }

      Rectangle {
        id: knob
        width: toggle.knobSize
        height: toggle.knobSize
        radius: root.radiusFor(Math.min(width, height))
        x: toggle.checked ? track.width - width - toggle.knobInset : toggle.knobInset
        anchors.verticalCenter: parent.verticalCenter
        color: toggle.checked ? root.foreground : Qt.darker(root.foreground, 1.25)
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
      NotchButton {
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
