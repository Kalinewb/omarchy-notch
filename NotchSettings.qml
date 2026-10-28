import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "keys.js" as KeyCombo
import "spring.js" as Spring
import "settings-tips.js" as Tips

// The notch's settings, drawn inside the notch itself: opening them grows the
// notch -- the same surface, top edge on the screen edge -- into this panel.
// Opened by a long right-click, by the hover action "Settings", or over IPC;
// closed by clicking outside, Escape, or the ✕.
//
// Quiet by default (plan-settings.md): nine rows under three headings, and
// one fold, Advanced, with the rest. A row is a label and its control, and the
// control says the state on the right. Every control reads the live value from
// the bar and writes straight to `bar.notch` in shell.json -- a row that sets
// two keys writes them in one batch (`bar.setNotchSettings`) -- so a change
// shows on the notch at once and survives a restart.
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
  signal pluginsRequested()

  readonly property real padding: Style.space(16)
  // The line under the list for the hovered row's tip (phase 3), reserved now.
  readonly property real footHeight: Style.space(24)
  implicitWidth: Style.space(400)
  implicitHeight: Math.min(maxHeight, headerHeight + column.implicitHeight + footHeight + padding)

  // Drawn on the notch, so colours come from the notch: text that reads on the
  // notch colour whatever the theme (see Bar.qml, "colours on the notch").
  readonly property color foreground: bar ? bar.notchForeground : "#ffffff"
  readonly property color accent: bar ? bar.notchAccent : "#ffffff"
  readonly property color surface: bar ? bar.notchColor : "#000000"
  readonly property color dim: bar ? bar.notchSecondaryText : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.6)
  // What the panel's own controls paint with (dev/colours.sh: no hue).
  readonly property var painted: [menuRow.trackColor, menuRow.knobColor, setupButton.selectedFill, setupButton.hoverFill]

  function radiusFor(height) { return bar ? bar.radiusFor(height) : Math.max(0, Math.min(10, height / 2)) }
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int rowHeight: Style.space(30)

  // Motion: a control settles on a spring (zeta 0.85, 200 ms) and fades in
  // 120 ms; the notch itself grows on the arrival spring when a fold opens.
  // OMARCHY_REDUCED_MOTION=1 (or NOTCH_REDUCED_MOTION) turns the moving parts into cuts.
  readonly property bool still: Quickshell.env("OMARCHY_REDUCED_MOTION") === "1" || Quickshell.env("NOTCH_REDUCED_MOTION") === "1"
  readonly property int settleMs: still ? 0 : 200
  readonly property int fadeMs: still ? 0 : 120
  readonly property var settleCurve: Spring.curve(0.85, 0.55, 8)

  function set(key, value) { if (bar) bar.setNotchSetting(key, value) }
  // Several keys in one write.
  function setMany(values) { if (bar) bar.setNotchSettings(values) }

  // `list` with `value` added, or taken out if it was there; `order`, when
  // given, keeps the list in that order whatever order things were picked in.
  function toggled(list, value, order) {
    var next = list.slice()
    var i = next.indexOf(value)
    if (i === -1) next.push(value)
    else next.splice(i, 1)
    if (order) next.sort(function(a, b) { return order.indexOf(a) - order.indexOf(b) })
    return next
  }

  // Options from "value=Label;value=Label".
  function opts(spec) {
    return spec.split(";").map(function(p) { var i = p.indexOf("="); return { value: p.slice(0, i), label: p.slice(i + 1) } })
  }
  readonly property var itemOrder: ["clock", "date", "media", "battery"]
  readonly property var itemOptions: opts("clock=Time;date=Date;media=Media;battery=Battery")
  // The bar's widgets, as options "plugin:<id>".
  readonly property var widgetOptions: (bar ? bar.layoutPluginChoices() : []).map(function(w) { return { value: "plugin:" + w.value, label: w.label } })

  // Plugins that declare an integration, whatever the notch made of it.
  readonly property var integrations: bar ? bar.platform.list : []
  // Widgets whose own panel the notch could draw, whether or not they know
  // anything about the notch. Read when the panel shows, not bound: the walk
  // touches every widget's children, and as a binding it re-ran on each
  // widget's creation (a warning per run, 18 MB of log in one startup).
  property var hostable: []
  function refreshHostable() { hostable = bar ? bar.hostableWidgets() : [] }

  // What is new: the notch's own update, and each plugin's verified update.
  // It counts what is known and never probes.
  readonly property int updates: !bar ? 0
    : (bar.updateCheckResult && bar.updateCheckResult.state === "available" ? 1 : 0)
      + bar.pluginsViews.filter(function(v) { return v.state === "update-available" }).length
  readonly property int issues: bar && bar.setup.enabled ? bar.setup.issueCount : 0

  // `enabled` follows the host's `shown` exactly, so this is "the panel is
  // being opened" with no dependence on the fade. Every fold starts closed.
  onEnabledChanged: if (enabled) {
    refreshHostable()
    advanced.open = false
    rows().forEach(function(row) { row.open = false })
  }
  Component.onCompleted: refreshHostable()

  // Show a plugin inside the notch or give it its own UI back (the list of ids
  // that are off is the setting), or draw a widget's own panel inside the
  // notch or give it back to its own window (takes effect on the next click;
  // a panel open right now is released).
  function togglePanel(value) {
    if (!bar) return
    var integration = value.indexOf("i:") === 0
    var id = value.slice(2)
    var key = integration ? "disabledIntegrations" : "hostedPanels"
    var list = integration ? bar.notchDisabledIntegrations || [] : bar.notchHostedPanels || []
    Qt.callLater(refreshHostable)
    if (!integration && list.indexOf(id) !== -1) bar.releaseHostedPanel()
    set(key, toggled(list, id))
  }

  function resetAll() {
    if (!bar || !bar.shell || typeof bar.shell.mutateShellConfig !== "function") return
    bar.batterySimulatedState = ""
    bar.shell.mutateShellConfig(function(config) {
      if (Util.isPlainObject(config.bar)) delete config.bar.notch
    })
  }

  // Scroll `item` into view.
  function reveal(item) {
    var y = item.mapToItem(column, 0, 0).y
    var view = settingsFlick
    if (y + item.height > view.contentY + view.height)
      view.contentY = Math.max(0, Math.min(y + item.height - view.height, view.contentHeight - view.height))
    else if (y < view.contentY) view.contentY = y
  }

  // Every row, in the order it is drawn: what the report and `press` walk.
  readonly property var groups: [look, opening, inside, advanced]
  function rows() { return groups.reduce(function(all, g) { return all.concat(g.rows()) }, []) }

  // The header's buttons, as the report and `press` see them.
  readonly property var headerButtons: [{ name: "updates", item: updatesButton }, { name: "setup", item: setupButton },
                                        { name: "guide", item: guideButton }, { name: "close", item: closeButton }]

  // dev/settings.sh reads this through Bar's settingsReport.panel.
  function report() {
    var header = headerButtons.filter(function(b) { return b.item.visible }).map(function(b) {
      return { name: b.name, text: b.item.text, x: Number(b.item.mapToItem(root, 0, 0).x.toFixed(1)), width: Number(b.item.width.toFixed(1)) }
    })
    return {
      rows: rows().map(function(r) {
        return { id: r.rid, section: r.parent.sectionName || "", depth: r.parent.sectionName !== undefined ? 1 : 2,
                 label: r.label, control: r.kind, controls: r.controlCount, state: r.stateText, tip: Tips.t[r.rid] || "",
                 helper: r.helper, attention: r.attention, visible: r.visible, dimmed: r.dimmed, open: r.open, keys: r.keys }
      }),
      sections: groups.map(function(g) { return g.title }),
      advanced: { open: advanced.open },
      contentHeight: settingsFlick.contentHeight, viewHeight: settingsFlick.height, footHeight: foot.height,
      header: [{ name: "title", text: "Notch", x: root.padding, width: Number(titleText.width.toFixed(1)) }].concat(header),
      badges: [{ name: "updates", count: updates }, { name: "setup", count: issues }].filter(function(b) { return b.count > 0 })
    }
  }

  // Test hook (Bar's settingsPress): the handler a click would use.
  function press(name) {
    var parts = String(name).split(":")
    if (parts[0] === "advanced") { advanced.open = !advanced.open; return "ok" }
    var found = parts[0] === "header" ? headerButtons.filter(function(b) { return b.name === parts[1] && b.item.visible })
      : parts[0] === "set" ? rows().filter(function(r) { return r.rid === parts[1] }) : []
    if (found.length === 0) return "no-such-button"
    if (parts[0] === "header") { found[0].item.clicked(); return "ok" }
    var raw = parts.slice(2).join(":")
    found[0].apply(found[0].kind === "switch" ? raw === "true" : found[0].kind === "stepper" ? Number(raw) : raw)
    return "ok"
  }

  focus: true
  Keys.onEscapePressed: root.closeRequested()

  // Header, on the resting notch's row. Badges are counts on its buttons,
  // shown only above 0, and a button appears only when it has a target.
  Item {
    x: root.padding
    width: parent.width - 2 * root.padding
    height: root.headerHeight

    Text {
      id: titleText
      anchors.verticalCenter: parent.verticalCenter
      text: "Notch"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      HeaderButton { id: updatesButton; visible: root.updates > 0; text: "Updates · " + root.updates; onClicked: root.pluginsRequested() }
      HeaderButton { id: setupButton; visible: !!root.bar && root.bar.setup.enabled; text: root.issues > 0 ? "Setup · " + root.issues : "Setup"; onClicked: root.setupRequested() }
      HeaderButton { id: guideButton; visible: !!root.bar && typeof root.bar.openWizard === "function"; text: "Guided setup"; onClicked: root.bar.openWizard() }
      HeaderButton { id: closeButton; text: "✕"; horizontalPadding: Style.space(8); onClicked: root.closeRequested() }
    }
  }

  Flickable {
    id: settingsFlick
    x: root.padding
    y: root.headerHeight
    width: parent.width - 2 * root.padding
    height: parent.height - root.headerHeight - root.padding - root.footHeight
    contentWidth: width
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: column
      width: parent.width
      spacing: Style.space(2)

      Group {
        id: look
        title: "Look"

        PickRow {
          rid: "atRest"; label: "At rest"; many: true; keys: ["compact"]
          none: "Nothing"
          options: root.itemOptions
          selected: root.bar ? root.bar.notchCompactItems : []
          onChosen: function(v) { root.set("compact", root.toggled(root.bar.notchCompactItems, v, root.itemOrder)) }
        }
        ToggleRow {
          rid: "autoHide"; label: "Auto-hide"; keys: ["autoHide"]
          checked: root.bar ? root.bar.notchAutoHide : false
        }

        PickRow {
          rid: "glow"; label: "Charging glow"; keys: ["batteryGlow", "glowStyle"]
          options: root.opts("off=Off;outline=Outline;bottom=Bottom")
          selected: [!root.bar ? "outline" : !root.bar.notchBatteryGlow ? "off" : root.bar.notchGlowStyle]
          onChosen: function(v) { root.setMany(v === "off" ? { batteryGlow: false } : { batteryGlow: true, glowStyle: v }) }
        }
      }

      Group {
        id: opening
        title: "Open"

        // A trigger another gesture already uses is shown, but not pickable.
        PickRow {
          rid: "openWith"; label: "Open with"; many: true; keys: ["openWith"]
          none: "Nothing"
          options: root.opts("hover=Hover;click=Click;doubleClick=Double-click;longPress=Long press;rightClick=Right-click;middleClick=Middle-click;scroll=Scroll")
          taken: root.bar ? root.bar.notchSettingsWith.concat(root.bar.notchMenuWith) : []
          selected: root.bar ? root.bar.notchOpenWith : []
          onChosen: function(v) { root.set("openWith", root.toggled(root.bar.notchOpenWith, v)) }
        }

        // Each widget is an option of its own, not a second row that appears.
        PickRow {
          rid: "opensTo"; label: "Opens to"; keys: ["openAction", "openPlugin"]
          options: root.opts("widgets=Widgets;clock=Clock;battery=Battery;settings=Settings;menu=Menu").concat(root.widgetOptions)
          selected: !root.bar ? [] : [root.bar.notchOpenAction === "plugin" ? "plugin:" + root.bar.notchOpenPlugin : root.bar.notchOpenAction]
          onChosen: function(v) { root.setMany(v.indexOf("plugin:") === 0 ? { openAction: "plugin", openPlugin: v.slice(7) } : { openAction: v }) }
        }
      }

      Group {
        id: inside
        title: "In the notch"

        // Omarchy's own toast still appears as well unless the notch is
        // "only": it is a second display of the same notification.
        PickRow {
          rid: "notifications"; label: "Notifications"; keys: ["notifications", "suppressNativeToast"]
          options: root.opts("toast=Notch + toast;only=Notch only;off=Off")
          selected: [!root.bar ? "toast" : !root.bar.notchNotifications ? "off" : root.bar.notchSuppressNativeToast ? "only" : "toast"]
          onChosen: function(v) { root.setMany(v === "off" ? { notifications: false } : { notifications: true, suppressNativeToast: v === "only" }) }
        }

        PickRow {
          rid: "notifyLight"; label: "Notification light"; keys: ["notificationLight"]
          options: root.opts("off=Off;notch=Around the notch;top=Top edge;full=Full screen")
          selected: [root.bar ? String(root.bar.notchSetting("notificationLight", "off")) : "off"]
          onChosen: function(v) { root.set("notificationLight", v) }
        }

        // The notch installs the companion plugin the routing needs
        // (Companion.keepInStep); Setup reports it if that fails.
        ToggleRow {
          id: menuRow
          rid: "menu"; label: "Menu"; keys: ["replaceMenu"]
          checked: root.bar ? root.bar.notchReplaceMenu : false
        }
        ToggleRow {
          rid: "volume"; label: "Volume and brightness"; keys: ["replaceOsd"]
          checked: root.bar ? root.bar.notchReplaceOsd : false
        }
      }

      // The rest, flat, in the order of use. Closed each time the panel opens.
      Group {
        id: advanced
        title: "Advanced"
        fold: true

        StepRow {
          rid: "width"; label: "Width"; keys: ["compactWidth"]
          value: root.bar ? Math.round(root.bar.notchCompactWidth) : 180; from: 100; to: 600; stepSize: 10; unit: "px"
          onChosen: function(v) { root.set("compactWidth", v) }
        }

        // Items and widgets in one list; dimmed when hover opens the notch.
        PickRow {
          rid: "onHover"; label: "On hover"; many: true; keys: ["hoverItems", "hoverPlugins"]
          none: "Nothing"
          dimmed: !!root.bar && root.bar.opensWith("hover")
          summary: dimmed ? "Hover opens" : ""
          options: root.itemOptions.concat(root.widgetOptions)
          selected: !root.bar ? [] : root.bar.notchHoverItems.concat(root.bar.notchHoverPlugins.map(function(id) { return "plugin:" + id }))
          onChosen: function(v) {
            if (v.indexOf("plugin:") === 0) root.set("hoverPlugins", root.toggled(root.bar.notchHoverPlugins, v.slice(7)))
            else root.set("hoverItems", root.toggled(root.bar.notchHoverItems, v, root.itemOrder))
          }
        }

        // A plugin declaring hideable: false can't be hidden.
        PickRow {
          rid: "hidden"; label: "Hidden widgets"; many: true; keys: ["hiddenPlugins"]
          options: root.widgetOptions.map(function(w) { return { value: w.value.slice(7), label: w.label } })
          taken: root.bar ? root.bar.notchPlugins.list.filter(function(p) { return p.hideable === false }).map(function(p) { return p.id }) : []
          selected: root.bar ? root.bar.notchHiddenPlugins : []
          summary: selected.length > 0 ? selected.length + " hidden" : "None"
          onChosen: function(v) { root.set("hiddenPlugins", root.toggled(root.bar.notchHiddenPlugins, v)) }
        }

        PickRow {
          rid: "openRow"; label: "Also in the widget row"; many: true; keys: ["expanded"]
          none: "Nothing"
          options: root.itemOptions
          selected: root.bar ? root.bar.notchExpandedItems : []
          onChosen: function(v) { root.set("expanded", root.toggled(root.bar.notchExpandedItems, v, root.itemOrder)) }
        }

        // Plugins that draw inside the notch, and widgets whose own panel the
        // notch can draw. Hidden until one says it can; a plugin the notch
        // does not accept says why, on its line.
        PickRow {
          rid: "panels"; label: "Panels"; many: true; keys: ["hostedPanels", "disabledIntegrations"]
          visible: root.integrations.length > 0 || root.hostable.length > 0
          options: root.integrations.map(function(i) { return { value: "i:" + i.id, label: (i.name || i.id) + (i.accepted ? "" : " · " + i.reasonText) } })
            .concat(root.hostable.map(function(h) { return { value: "h:" + h.id, label: h.name } }))
          selected: root.integrations.filter(function(i) { return !i.userOff }).map(function(i) { return "i:" + i.id })
            .concat(root.hostable.filter(function(h) { return h.hosted }).map(function(h) { return "h:" + h.id }))
          summary: selected.length + " of " + options.length
          attention: root.integrations.some(function(i) { return !i.accepted })
          helper: attention ? root.integrations.filter(function(i) { return !i.accepted })[0].reasonText : ""
          onOpenChanged: if (open) root.refreshHostable()
          onChosen: function(v) { root.togglePanel(v) }
        }

        // One number rounds both the lower corners and the edge curves.
        StepRow {
          rid: "corners"; label: "Corners"; keys: ["bottomRadius", "filletRadius"]
          value: root.bar ? Math.round(root.bar.notchBottomRadius) : 10; from: 0; to: 24; stepSize: 1
          shown: !root.bar || Math.round(root.bar.notchBottomRadius) === Math.round(root.bar.notchFilletRadius) ? ""
            : value + " / " + Math.round(root.bar.notchFilletRadius) + " px"
          unit: "px"
          onChosen: function(v) { root.setMany({ bottomRadius: v, filletRadius: v }) }
        }

        PickRow {
          rid: "notifyTime"; label: "Notification time"; keys: ["notificationStay", "notificationSeconds"]
          dimmed: !!root.bar && !root.bar.notchNotifications
          readonly property string current: !root.bar ? "6" : root.bar.notchNotificationStay ? "stay" : String(root.bar.notchNotificationSeconds)
          // Another stored value shows as itself.
          options: root.opts("stay=Until I act;3=3 s;6=6 s;10=10 s;30=30 s").concat(["stay", "3", "6", "10", "30"].indexOf(current) === -1 ? [{ value: current, label: current + " s" }] : [])
          selected: [current]
          onChosen: function(v) { root.setMany(v === "stay" ? { notificationStay: true } : { notificationStay: false, notificationSeconds: Number(v) }) }
        }

        PickRow {
          rid: "lightColours"; label: "Light colours"; keys: ["notificationLightColours"]
          dimmed: !root.bar || root.bar.notchSetting("notificationLight", "off") === "off"
          options: root.opts("aurora=Aurora;blue=Blue;white=White")
          selected: [root.bar ? String(root.bar.notchSetting("notificationLightColours", "aurora")) : "aurora"]
          onChosen: function(v) { root.set("notificationLightColours", v) }
        }

        PickRow {
          rid: "peeks"; label: "Peeks"; many: true; keys: ["peekOnTrackChange", "batteryPeek"]
          none: "Off"
          options: root.opts("peekOnTrackChange=New track;batteryPeek=Plug-in and low battery")
          selected: !root.bar ? [] : (root.bar.notchPeekOnTrackChange ? ["peekOnTrackChange"] : []).concat(root.bar.notchBatteryPeek ? ["batteryPeek"] : [])
          summary: selected.length === 2 ? "Both" : ""
          onChosen: function(v) { root.set(v, selected.indexOf(v) === -1) }
        }

        // Relative to the resting notch's size (100 % reaches 32 px on the
        // default 180 × 32 notch, further on a bigger one; at most 80 px).
        StepRow {
          rid: "glowSize"; label: "Glow size"; keys: ["glowScale"]
          value: root.bar ? Math.round(root.bar.notchGlowScale * 100) : 100; from: 0; to: 250; stepSize: 5; unit: "%"
          onChosen: function(v) { root.set("glowScale", v / 100) }
        }
        StepRow {
          rid: "greenAbove"; label: "Green from"; keys: ["greenAbove"]
          value: root.bar ? root.bar.notchGreenAbove : 100; from: 0; to: 100; stepSize: 5; unit: "%"
          onChosen: function(v) { root.set("greenAbove", v) }
        }
        StepRow {
          rid: "lowBelow"; label: "Low battery at"; keys: ["lowBattery"]
          value: root.bar ? root.bar.notchLowBattery : 20; from: 5; to: 60; stepSize: 5; unit: "%"
          onChosen: function(v) { root.set("lowBattery", v) }
        }

        // The four keys the panel offers. The recorder's clash check reads all
        // six, so a hand-set menuKey or stateKey is protected too.
        SettingRow {
          id: keybindsRow
          rid: "keybinds"; label: "Keybinds"; kind: "keyRecord"; foldable: true
          keys: ["openKey", "settingsKey", "autoHideKey", "stayOpenKey"]
          readonly property var combos: !root.bar ? [] : [root.bar.notchOpenKey, root.bar.notchSettingsKey, root.bar.notchAutoHideKey, root.bar.notchStayOpenKey]
          readonly property int count: combos.filter(function(c) { return c !== "" }).length
          stateText: count > 0 ? count + " set" : "None"
          lines: [
            KeyLine { label: "Open the notch"; key: "openKey"; current: keybindsRow.combos[0] || "" },
            KeyLine { label: "Open settings"; key: "settingsKey"; current: keybindsRow.combos[1] || "" },
            KeyLine { label: "Auto-hide"; key: "autoHideKey"; current: keybindsRow.combos[2] || "" },
            KeyLine { label: "Keep it open"; key: "stayOpenKey"; current: keybindsRow.combos[3] || "" }
          ]
        }
        ToggleRow {
          rid: "stayOpen"; label: "Keep open"; keys: ["stayOpen"]
          checked: root.bar ? root.bar.notchStayOpen : false
        }

        // Follows Auto-hide until set; a user who set it must be able to undo it.
        ToggleRow {
          rid: "windowsToTop"; label: "Windows to the top"; keys: ["windowsToTop"]
          checked: root.bar ? root.bar.notchWindowsToTop : false
        }
        ToggleRow {
          rid: "updateCheck"; label: "Check for updates"; keys: ["updateCheck"]
          checked: root.bar ? root.bar.notchUpdateCheck : true
        }

        // plan-export.md's rows: hidden until the notch can export.
        ButtonRow {
          rid: "share"; label: "Share settings"
          visible: !!root.bar && typeof root.bar.shareSettings === "function"
          buttons: [ActionButton { text: "Copy code"; onClicked: root.bar.shareSettings("copy") },
                    ActionButton { text: "Save file"; onClicked: root.bar.shareSettings("file") }]
        }

        ButtonRow {
          rid: "importer"; label: "Use someone's settings"
          visible: !!root.bar && typeof root.bar.importSettings === "function"
          buttons: ActionButton { text: "Import"; onClicked: root.bar.importSettings() }
        }

        // Deletes `bar.notch` with no undo.
        ButtonRow {
          rid: "reset"; label: "Reset to defaults"
          buttons: ActionButton { text: "Reset"; onClicked: root.resetAll() }
        }
      }
    }
  }

  Item {
    id: foot
    x: root.padding
    y: parent.height - root.padding - height
    width: parent.width - 2 * root.padding
    height: root.footHeight
  }

  // A heading and its rows; with `fold`, the heading opens and closes them.
  component Group: Column {
    id: group
    property string title: ""
    property bool fold: false
    property bool open: !fold
    default property alias content: body.data
    width: parent ? parent.width : 0
    spacing: Style.space(2)
    function rows() { return Array.prototype.slice.call(body.children).filter(function(c) { return c.rid !== undefined }) }

    Item {
      width: parent.width
      height: Style.space(group.fold ? 30 : 26)

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: group.fold ? group.title + "  " + (group.open ? "▾" : "▸") : group.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      MouseArea {
        anchors.fill: parent
        enabled: group.fold
        cursorShape: Qt.PointingHandCursor
        onClicked: group.open = !group.open
      }
    }

    Column {
      id: body
      property string sectionName: group.title
      width: parent.width
      spacing: Style.space(2)
      opacity: group.open ? 1 : 0
      visible: group.open || opacity > 0
      Behavior on opacity { NumberAnimation { duration: root.fadeMs; easing.type: Easing.OutCubic } }
    }
  }

  // A label and its control, nothing else; the state is the control's value.
  // A `foldable` row says its state with a chevron and unfolds its own option
  // lines in place, flat and without tips.
  component SettingRow: Column {
    id: row
    property string rid: ""
    property string label: ""
    // The control: switch pick pickMany stepper keyRecord button.
    property string kind: "switch"
    property var keys: []
    property string stateText: ""
    // Text beyond label and state is allowed only as an attention state.
    property bool attention: false
    property string helper: ""
    property bool dimmed: false
    property bool foldable: false
    property bool open: false
    readonly property int controlCount: slot.children.length
    readonly property Item foldBody: fold
    signal chosen(var value)
    default property alias control: slot.data
    property alias lines: fold.data

    // What a click or a key does to this row's control.
    function apply(value) {
      chosen(value)
      if (kind === "pick") open = false
    }

    width: parent ? parent.width : 0
    opacity: dimmed ? 0.45 : 1
    onOpenChanged: if (open) Qt.callLater(function() { root.reveal(row) })

    Item {
      width: parent.width
      height: Math.max(root.rowHeight, slot.height)

      Text {
        anchors.left: parent.left
        anchors.right: row.foldable ? stateLabel.left : slot.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        text: row.label
        elide: Text.ElideRight
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      MouseArea {
        anchors.fill: parent
        enabled: row.foldable
        cursorShape: Qt.PointingHandCursor
        onClicked: row.open = !row.open
      }

      Text {
        id: stateLabel
        visible: row.foldable
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width * 0.6)
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        text: row.stateText + (row.open ? "  ▴" : "  ▾")
        color: root.foreground
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

    Column {
      id: fold
      x: Style.space(10)
      width: parent.width - x
      spacing: Style.space(2)
      bottomPadding: Style.space(4)
      opacity: row.open ? 1 : 0
      visible: row.foldable && (row.open || opacity > 0)
      Behavior on opacity { NumberAnimation { duration: root.fadeMs; easing.type: Easing.OutCubic } }
    }
  }

  // One of three or more (`many: false`), or a set (`many: true`), unfolding
  // its options in place. `selected` holds the values shown as chosen; `taken`
  // are options shown but not pickable.
  component PickRow: SettingRow {
    id: pick
    property var options: []
    property var selected: []
    property var taken: []
    property bool many: false
    // The state when nothing is picked; a summary replaces the names.
    property string none: "None"
    property string summary: ""
    kind: many ? "pickMany" : "pick"
    foldable: true
    stateText: {
      if (summary !== "") return summary
      var names = options.filter(function(o) { return selected.indexOf(o.value) !== -1 }).map(function(o) { return o.label })
      return names.length === 0 ? none : names.length <= 3 ? names.join(", ") : names.length + " picked"
    }
    lines: Repeater {
      model: pick.open || pick.foldBody.visible ? pick.options : []
      OptionLine {
        required property var modelData
        text: modelData.label
        on: pick.selected.indexOf(modelData.value) !== -1
        enabled: pick.taken.indexOf(modelData.value) === -1
        onClicked: pick.apply(modelData.value)
      }
    }
  }

  component ToggleRow: SettingRow {
    id: toggle
    property bool checked: false
    readonly property color trackColor: toggleSwitch.trackColor
    readonly property color knobColor: toggleSwitch.knobColor
    kind: "switch"
    stateText: checked ? "On" : "Off"
    onChosen: function(v) { root.set(keys[0], v) }
    Switch {
      id: toggleSwitch
      checked: toggle.checked
      onToggled: toggle.apply(!checked)
    }
  }

  // A number with steps; `shown` replaces "<value> <unit>" ("8 / 12 px").
  component StepRow: SettingRow {
    id: step
    property int value: 0
    property int from: 0
    property int to: 100
    property int stepSize: 1
    property string unit: ""
    property string shown: ""
    kind: "stepper"
    stateText: shown !== "" ? shown : value + " " + unit
    NotchNumberField {
      foreground: root.foreground
      accent: root.accent
      fieldWidth: Style.space(92)
      suffix: " " + step.unit
      display: step.shown
      // The box and its up/down buttons take their corners from the theme;
      // give them the notch's.
      Component.onCompleted: {
        if (!field) return
        var parts = [field.background, field.up ? field.up.indicator : null, field.down ? field.down.indicator : null]
        parts.forEach(function(part) {
          if (part && part.radius !== undefined)
            part.radius = Qt.binding(function() { return root.radiusFor(Math.min(part.height, part.width)) })
        })
      }
      value: step.value
      from: step.from
      to: step.to
      stepSize: step.stepSize
      fontFamily: root.fontFamily
      onModified: function(v) { step.apply(v) }
    }
  }

  component ButtonRow: SettingRow {
    kind: "button"
    property alias buttons: buttonRow.data
    Row { id: buttonRow; spacing: Style.space(6) }
  }

  component ActionButton: NotchButton {
    foreground: root.foreground
    accent: root.accent
    radius: root.radiusFor(Math.min(width, height))
    bordered: true
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    horizontalPadding: Style.space(7)
  }

  component HeaderButton: NotchButton {
    foreground: root.foreground
    accent: root.accent
    radius: root.radiusFor(Math.min(width, height))
    fontFamily: root.fontFamily
    horizontalPadding: Style.space(10)
  }

  // One option of a Pick, a flat line in the row's fold. The mark is not the
  // fill alone: the chosen one carries a tick.
  component OptionLine: NotchButton {
    property bool on: false
    width: parent ? parent.width : 0
    height: Style.space(26)
    leftAlign: true
    selected: on
    foreground: root.foreground
    accent: root.accent
    radius: root.radiusFor(Math.min(width, height))
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    horizontalPadding: Style.space(10)
    opacity: enabled ? 1 : 0.35

    Text {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      visible: parent.on
      text: "✓"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // A Hyprland key combination: the current one, a Record button that listens
  // for the next key press (Escape cancels), and ✕ to remove it. Saved on record.
  component KeyLine: Item {
    id: keyLine
    property string label: ""
    property string key: ""
    property string current: ""
    property bool recording: false
    property string hint: ""
    width: parent ? parent.width : 0
    height: Style.space(28)

    // Every notch keybind: one combination can't be recorded twice.
    function usedBy(combo) {
      if (!root.bar) return ""
      var others = { openKey: root.bar.notchOpenKey, settingsKey: root.bar.notchSettingsKey, autoHideKey: root.bar.notchAutoHideKey,
                     menuKey: root.bar.notchMenuKey, stayOpenKey: root.bar.notchStayOpenKey, stateKey: root.bar.notchStateKey }
      var labels = { openKey: "the notch", settingsKey: "settings", autoHideKey: "auto-hide", menuKey: "the menu",
                     stayOpenKey: "keep open", stateKey: "close and reopen" }
      for (var k in others) if (k !== keyLine.key && others[k] === combo) return labels[k]
      return ""
    }

    function stop() { recording = false; root.forceActiveFocus() }

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: keyLine.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: keyLine.recording ? (keyLine.hint || "press keys…") : (keyLine.hint || (keyLine.current || "none"))
        color: keyLine.recording || keyLine.hint ? root.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      ActionButton {
        text: keyLine.recording ? "Cancel" : "Record"
        onClicked: {
          keyLine.hint = ""
          if (keyLine.recording) { keyLine.stop(); return }
          keyLine.recording = true
          catcher.forceActiveFocus()
        }
      }

      ActionButton {
        visible: keyLine.current !== "" && !keyLine.recording
        text: "✕"
        horizontalPadding: Style.space(6)
        onClicked: { keyLine.hint = ""; root.set(keyLine.key, "") }
      }
    }

    Item {
      id: catcher
      focus: keyLine.recording
      Keys.onPressed: function(event) {
        if (!keyLine.recording) return
        event.accepted = true
        if (event.key === KeyCombo.ESCAPE) { keyLine.hint = ""; keyLine.stop(); return }
        var result = KeyCombo.combo(event.key, event.modifiers)
        if (result.waiting) return
        if (!result.combo) { keyLine.hint = result.reason; return }
        var clash = keyLine.usedBy(result.combo)
        if (clash) { keyLine.hint = result.combo + " is used by " + clash; return }
        keyLine.hint = ""
        root.set(keyLine.key, result.combo)
        keyLine.stop()
      }
      onActiveFocusChanged: if (!activeFocus && keyLine.recording) keyLine.recording = false
    }
  }

  // Omarchy's ToggleSwitch, with the notch's colours and radius. `toggled`
  // fires before `checked` changes, as ToggleSwitch's does. The knob settles
  // on the controls' spring; a press dips to 0.97.
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
    scale: switchMouse.pressed ? 0.97 : 1
    Behavior on scale {
      NumberAnimation {
        duration: root.still ? 0 : switchMouse.pressed ? 60 : root.settleMs
        easing.type: switchMouse.pressed ? Easing.OutCubic : Easing.BezierSpline
        easing.bezierCurve: root.settleCurve
      }
    }

    // Fills are the text colour at the theme's alpha (NotchButton.qml).
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
      Behavior on color { ColorAnimation { duration: root.still ? 0 : 90 } }

      Rectangle {
        id: knob
        width: toggle.knobSize
        height: toggle.knobSize
        radius: root.radiusFor(Math.min(width, height))
        x: toggle.checked ? track.width - width - toggle.knobInset : toggle.knobInset
        anchors.verticalCenter: parent.verticalCenter
        color: toggle.checked ? root.foreground : Qt.darker(root.foreground, 1.25)
        Behavior on x { NumberAnimation { duration: root.settleMs; easing.type: Easing.BezierSpline; easing.bezierCurve: root.settleCurve } }
        Behavior on color { ColorAnimation { duration: root.still ? 0 : 90 } }
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
}
