import QtQuick
import qs.Commons
import qs.Ui
import "PluginsModel.js" as PluginsModel

// The Plugins page, drawn inside the notch: opening it grows the notch -- the
// same surface, top edge on the screen edge -- into this list of the user's
// own plugins (plugins/catalogue.json), each with what it is doing and what
// can be done about it. Install… and Update… replace the list with a
// confirmation card; nothing runs until it is confirmed.
//
// A pure view: it reads the notch's Bar.qml root (see Bar.qml, "plugins") and
// calls its functions, and starts nothing itself. On the notch's colours and
// radius (DESIGN-PHILOSOPHY.md).
//
// Keys: Up/Down pick an entry, Enter presses its primary button, Escape
// closes. On the card Cancel has focus, Tab moves, Enter presses, Escape
// cancels.
//
// The list and the card are two layers on one surface (DESIGN-PHILOSOPHY.md,
// 4): the list fades out over 90 ms, then the card fades in over 220 ms, and
// back. The page keeps the taller of the two until the card has faded out, so
// the notch only ever resizes around content that isn't changing.
Item {
  id: root

  // The notch's Bar.qml root, and the BarPanel window it is drawn in.
  property var bar: null
  property var window: null
  // How tall the notch may grow for this page; past that it scrolls.
  property real maxHeight: 600
  // The notch's resting height: the header sits on that row.
  property real headerHeight: 32
  // The entry to open on ("" for the top).
  property string focusId: ""
  signal closeRequested()
  signal backRequested()

  readonly property real padding: Style.space(16)
  implicitWidth: Style.space(400)
  // The page's height with the list, and with the card; held at the taller
  // while the card shows or is still fading.
  readonly property real listHeight: Math.min(maxHeight, headerHeight + list.implicitHeight + padding)
  readonly property real cardHeight: Math.min(maxHeight, headerHeight + card.implicitHeight + padding)
  readonly property bool holdCard: carding || cardOpacity > 0
  implicitHeight: holdCard ? Math.max(listHeight, cardHeight) : listHeight
  property real listOpacity: 1
  property real cardOpacity: 0

  readonly property color foreground: bar ? bar.notchForeground : "#ffffff"
  readonly property color secondary: bar ? bar.notchSecondaryText : Qt.rgba(235 / 255, 235 / 255, 245 / 255, 0.6)
  readonly property color accent: bar ? bar.notchAccent : "#ffffff"
  readonly property color surface: bar ? bar.notchColor : "#000000"
  readonly property color selectedFill: Util.alpha(foreground, Style.selectedFillAlpha)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function radiusFor(size) { return bar ? bar.radiusFor(size) : Math.max(0, Math.min(10, size / 2)) }
  function shortSha(sha) { return String(sha || "").slice(0, 7) }

  readonly property var views: bar ? bar.pluginsViews : []
  readonly property var rows: views.concat(bar ? [bar.pluginsSelfView] : [])
  readonly property var confirm: bar && bar.pluginsConfirm ? bar.pluginsConfirm : ({})
  readonly property var preview: bar && bar.pluginsPreview ? bar.pluginsPreview : ({})
  readonly property bool carding: !!confirm.id
  readonly property bool ready: !!bar && bar.pluginsConfirmReady
  readonly property var cardEntry: {
    var listed = bar && bar.pluginsCatalogue ? (bar.pluginsCatalogue.plugins || []) : []
    for (var i = 0; i < listed.length; i++) if (listed[i].id === confirm.id) return listed[i]
    return { id: confirm.id, name: confirm.id, url: "" }
  }
  property int selectedIndex: 0

  focus: true
  Keys.onPressed: function(event) {
    var names = {}
    names[Qt.Key_Escape] = "escape"; names[Qt.Key_Up] = "up"; names[Qt.Key_Down] = "down"
    names[Qt.Key_Return] = "return"; names[Qt.Key_Enter] = "return"; names[Qt.Key_Tab] = "tab"; names[Qt.Key_Backtab] = "backtab"
    if (names[event.key] !== undefined) event.accepted = root.handleKey(names[event.key])
  }

  // The card's keyboard focus: "cancel", "confirm" or "review".
  property string cardFocus: "cancel"
  readonly property string focusName: carding ? cardFocus : "list"

  // One key, for real key presses and pluginsPress "key:<name>" alike.
  // Returns whether it was used.
  function handleKey(name) {
    if (name === "escape") { cancelOrClose(); return true }
    if (carding) {
      var order = ["cancel"]
      if (confirmButton.visible && confirmButton.enabled) order.push("confirm")
      if (reviewButton.visible) order.push("review")
      if (name === "tab" || name === "backtab") {
        var at = Math.max(0, order.indexOf(cardFocus))
        focusCard(order[(at + (name === "tab" ? 1 : order.length - 1)) % order.length])
        return true
      }
      if (name === "return") {
        var b = cardButton(cardFocus)
        if (b && b.visible && b.enabled) b.clicked()
        return true
      }
      return false
    }
    if (name === "down" || name === "up") {
      selectedIndex = Math.max(0, Math.min(rows.length - 1, selectedIndex + (name === "down" ? 1 : -1)))
      ensureVisible()
      return true
    }
    if (name === "return") { pressPrimary(selectedIndex); return true }
    return false
  }

  function cardButton(name) { return name === "confirm" ? confirmButton : name === "review" ? reviewButton : cancelButton }
  function focusCard(name) {
    cardFocus = name
    cardButton(name).forceActiveFocus()
  }

  onEnabledChanged: if (enabled) { if (bar) bar.refreshPluginsIfStale(); applyFocusId() }
  onFocusIdChanged: applyFocusId()
  // A card left open when the page closed is cancelled once the page has faded
  // out, so it never changes under the shrinking notch.
  onVisibleChanged: if (!visible && bar) bar.cancelPluginAction()
  onCardingChanged: {
    toCard.stop(); toList.stop()
    if (!visible) {
      // Nothing on show: no fade.
      listOpacity = carding ? 0 : 1
      cardOpacity = carding ? 1 : 0
    } else if (carding) {
      toCard.start()
    } else {
      toList.start()
    }
    recordMotion()
    if (carding) {
      flick.contentY = 0
      Qt.callLater(function() { root.focusCard("cancel") })
    } else {
      root.forceActiveFocus()
    }
  }
  SequentialAnimation {
    id: toCard
    NumberAnimation { target: root; property: "listOpacity"; to: 0; duration: 90; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "cardOpacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
  }
  SequentialAnimation {
    id: toList
    NumberAnimation { target: root; property: "cardOpacity"; to: 0; duration: 90; easing.type: Easing.OutCubic }
    NumberAnimation { target: root; property: "listOpacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
  }

  // Test notches record 0.9 s of the notch's drawn height against the page's
  // after the card opens or closes, every 16 ms (dev/plugins.sh).
  property var motionSamples: []
  property var pendingSamples: []
  property real motionStart: 0
  function recordMotion() {
    if (!bar || !bar.harnessed || !window) return
    pendingSamples = []
    motionStart = Date.now()
    motionSampler.restart()
  }
  Timer {
    id: motionSampler
    interval: 16
    repeat: true
    onTriggered: {
      var t = Date.now() - root.motionStart
      root.pendingSamples.push({ t: t, drawn: Number(root.window.shownHeight.toFixed(3)), held: Number(root.implicitHeight.toFixed(3)),
                                 list: Number(root.listHeight.toFixed(3)), card: Number(root.cardOpacity.toFixed(3)),
                                 listOpacity: Number(root.listOpacity.toFixed(3)) })
      if (t >= 900) { stop(); root.motionSamples = root.pendingSamples.slice() }
    }
  }

  // Whether Refresh takes a click (dev/plugins.sh).
  readonly property bool refreshEnabled: refreshButton.enabled

  // Where the selected entry sits in the scrolled page (dev/plugins.sh).
  function scrollReport() {
    var item = entryRepeater.itemAt(selectedIndex)
    return { contentY: flick.contentY, viewHeight: flick.height, contentHeight: flick.contentHeight,
             selectedTop: item ? item.y : -1, selectedBottom: item ? item.y + item.height : -1,
             selectedShown: !!item && item.y >= flick.contentY - 0.5 && item.y + item.height <= flick.contentY + flick.height + 0.5 }
  }

  function applyFocusId() {
    selectedIndex = 0
    for (var i = 0; i < rows.length; i++) if (focusId && rows[i].id === focusId) selectedIndex = i
    if (!focusId) flick.contentY = 0
    Qt.callLater(ensureVisible)
  }

  function ensureVisible() {
    var item = entryRepeater.itemAt(selectedIndex)
    if (!item) return
    if (item.y < flick.contentY) flick.contentY = item.y
    else if (item.y + item.height > flick.contentY + flick.height) flick.contentY = item.y + item.height - flick.height
  }

  function cancelOrClose() {
    if (carding) bar.cancelPluginAction()
    else closeRequested()
  }

  function pressPrimary(index) {
    var row = rows[index]
    if (!row) return false
    for (var i = 0; i < row.actions.length; i++)
      if (row.actions[i].primary && row.actions[i].enabled) { run(row.actions[i].name); return true }
    return false
  }

  // One entry button: "<action>:<id>". Install and Update only open the card.
  function run(name) {
    if (!bar) return
    var at = name.indexOf(":")
    var kind = name.slice(0, at), id = name.slice(at + 1)
    switch (kind) {
      case "install": case "update": bar.askPluginAction(kind, id); break
      case "enable": bar.enablePlugin(id); break
      case "setup": bar.openPluginSetup(id); break
      case "remove": bar.openPluginRemoval(id); break
      case "review": bar.reviewPluginInTerminal(id); break
      case "dismiss":
        if (bar.pluginsHandoff && bar.pluginsHandoff.id === id && bar.pluginsHandoff.ok === false) bar.clearPluginHandoff()
        else bar.ackPluginJob()
        break
      case "updates": if (window) window.openSettingsSection("updates"); break
    }
  }

  // pluginsPress (dev/plugins.sh): the button's own click handler, if it is on
  // show. "ok", "disabled" or "no-such-button".
  function press(name) {
    var n = String(name)
    if (n.indexOf("key:") === 0) return handleKey(n.slice(4)) ? "ok" : "no-such-button"
    if (n === "escape") { cancelOrClose(); return "ok" }
    if (n === "close") { closeRequested(); return "ok" }
    if (n === "refresh") { if (!refreshButton.enabled) return "disabled"; bar.refreshPlugins(); return "ok" }
    if (carding) {
      if (n === "cancel") { cancelButton.clicked(); return "ok" }
      if (n === "confirm") { if (!confirmButton.visible) return "no-such-button"; if (!confirmButton.enabled) return "disabled"; confirmButton.clicked(); return "ok" }
      if (n === "review-diff" && reviewButton.visible) { reviewButton.clicked(); return "ok" }
      return "no-such-button"
    }
    for (var i = 0; i < rows.length; i++)
      for (var j = 0; j < rows[i].actions.length; j++)
        if (rows[i].actions[j].name === n) {
          if (!rows[i].actions[j].enabled) return "disabled"
          selectedIndex = i
          run(n)
          return "ok"
        }
    return "no-such-button"
  }

  // Header, on the resting notch's row.
  Item {
    x: root.padding
    width: parent.width - 2 * root.padding
    height: root.headerHeight

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "Plugins"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Button {
        id: refreshButton
        text: root.bar && root.bar.pluginsStateProcessRunning ? "Checking…" : "Refresh"
        // Not while a job runs: a fetch would race the checkout it changes.
        enabled: !!root.bar && root.bar.pluginsCanAct && !root.carding && !root.bar.pluginsStateProcessRunning && !root.bar.pluginJobRunning
        opacity: enabled ? 1 : 0.35
        foreground: root.foreground
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.space(8)
        onClicked: root.bar.refreshPlugins()
      }

      Button {
        text: "‹ Setup"
        foreground: root.foreground
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.space(8)
        onClicked: root.backRequested()
      }

      Button {
        text: "✕"
        foreground: root.foreground
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
        fontFamily: root.fontFamily
        horizontalPadding: Style.space(8)
        onClicked: root.closeRequested()
      }
    }
  }

  Flickable {
    id: flick
    x: root.padding
    y: root.headerHeight
    width: parent.width - 2 * root.padding
    height: parent.height - root.headerHeight - root.padding
    contentWidth: width
    contentHeight: root.implicitHeight - root.headerHeight - root.padding
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // The list: one row per entry, then the notch's own row, then why.
    Column {
      id: list
      opacity: root.listOpacity
      enabled: !root.carding && opacity > 0
      width: parent.width
      spacing: Style.space(2)

      Repeater {
        id: entryRepeater
        model: root.rows
        EntryRow {
          required property var modelData
          required property int index
          view: modelData
          rowIndex: index
        }
      }

      Text {
        width: parent.width
        topPadding: Style.space(6)
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: {
          var b = root.bar
          var lines = []
          if (b && !b.pluginsCanAct) lines.push("Test notch: plugins aren't checked.")
          else if (b && b.pluginsState && b.pluginsState.reason) lines.push(PluginsModel.reasonWords(b.pluginsState.reason, ""))
          else if (b && b.pluginsState && b.pluginsState.shell === false) lines.push(PluginsModel.reasonWords("not-running", ""))
          lines.push("Only these plugins can be installed here. Anything that needs your password is set up in the plugin's own panel.")
          return lines.join("\n")
        }
        color: root.secondary
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // The confirmation card, on the same surface.
    Column {
      id: card
      opacity: root.cardOpacity
      enabled: root.carding
      width: parent.width
      spacing: Style.space(6)
      topPadding: Style.space(4)

      // Kept while the card fades out, so its words don't change under it.
      property string action: "install"
      property string name: ""
      property string url: ""
      property string pluginId: ""
      readonly property bool install: action === "install"
      readonly property var commits: card.p.commits || []
      // The repository isn't this plugin any more (or couldn't be reached).
      readonly property string refused: String(card.p.refused || "")
      property var p: ({})
      property bool ready: false
      Connections {
        target: root
        function onConfirmChanged() {
          if (!root.confirm.id) return
          card.action = String(root.confirm.action || "install")
          card.name = String(root.cardEntry.name || root.confirm.id || "")
          card.url = String(root.cardEntry.url || "")
          card.pluginId = String(root.confirm.id)
          card.p = root.preview
          card.ready = root.ready
        }
        function onPreviewChanged() { if (root.carding) card.p = root.preview }
        function onReadyChanged() { if (root.carding) card.ready = root.ready }
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: (card.install ? "Install " : "Update ") + card.name + "?"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.DemiBold
      }

      Text {
        width: parent.width
        wrapMode: Text.WrapAnywhere
        textFormat: Text.PlainText
        text: {
          if (card.install)
            return card.url.replace(/^[a-z]+:\/\//, "") + " → " + card.pluginId
              + (card.ready ? "  (commit " + root.shortSha(card.p.remote) + ")" : "")
          if (!card.ready) return card.url.replace(/^[a-z]+:\/\//, "")
          var n = Number(card.p.behind || 0), f = Number(card.p.files || 0)
          return n + (n === 1 ? " commit" : " commits") + " · " + f + (f === 1 ? " file" : " files")
            + ", +" + Number(card.p.insertions || 0) + " −" + Number(card.p.deletions || 0)
        }
        color: root.secondary
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Repeater {
        model: card.install ? [] : card.commits.slice(0, 5)
        Text {
          required property var modelData
          width: card.width
          elide: Text.ElideRight
          textFormat: Text.PlainText
          text: "·  " + String(modelData.subject || "") + "  " + root.shortSha(modelData.sha)
          color: root.secondary
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: {
          var lines = []
          if (card.refused === "wrong-id" || card.refused === "bar-kind") {
            return (card.refused === "wrong-id" ? "This repository isn't " + card.name + " any more."
                                                : "This repository is a bar now, not " + card.name + ".")
              + (card.install ? " Nothing was installed." : " Nothing was updated.")
          }
          if (card.install) {
            lines.push("Plugins run unsandboxed inside your shell. It's added to your bar and turned on.")
            lines.push("Anything " + card.name + " needs your password for is set up in its own panel, not here.")
          } else {
            lines.push("Plugins run unsandboxed inside your shell.")
            if (card.p.panelOpen === true) lines.push("Updating closes " + card.name + "'s panel.")
            if (card.p.restartLikely === true) lines.push("The shell may need a restart to load every file.")
            if (card.p.pluginBusy === true) lines.push(PluginsModel.reasonWords("plugin-busy", card.name))
          }
          if (root.bar && root.bar.pluginJobRunning) lines.push(PluginsModel.reasonWords("busy", card.name))
          else if (card.p.id && !card.ready && card.p.ok === false)
            lines.push(card.p.reason === "current" ? "It's already up to date." : PluginsModel.reasonWords(card.p.reason, card.name))
          return lines.join("\n")
        }
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Item {
        width: parent.width
        height: cardButtons.height + Style.space(4)

        Button {
          id: reviewButton
          anchors.left: parent.left
          anchors.verticalCenter: cardButtons.verticalCenter
          visible: !card.install && card.ready
          text: "Review full diff in terminal"
          focusable: true
          onActiveFocusChanged: if (activeFocus) root.cardFocus = "review"
          foreground: root.secondary
          accent: root.accent
          radius: root.radiusFor(Math.min(width, height))
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(4)
          onClicked: root.bar.reviewPluginInTerminal(root.confirm.id)
        }

        Row {
          id: cardButtons
          anchors.right: parent.right
          y: Style.space(4)
          spacing: Style.space(6)

          Button {
            id: cancelButton
            // Refused: nothing to cancel, only to close.
            text: card.refused !== "" ? "Close" : "Cancel"
            focusable: true
            onActiveFocusChanged: if (activeFocus) root.cardFocus = "cancel"
            bordered: true
            foreground: root.foreground
            background: root.surface
            accent: root.accent
            radius: root.radiusFor(Math.min(width, height))
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(10)
            onClicked: root.bar.cancelPluginAction()
          }

          Button {
            id: confirmButton
            text: card.ready ? (card.install ? "Install" : "Update") : card.p.id ? (card.install ? "Install" : "Update") : "Checking…"
            visible: card.refused === ""
            enabled: card.ready
            opacity: enabled ? 1 : 0.35
            focusable: true
            onActiveFocusChanged: if (activeFocus) root.cardFocus = "confirm"
            bordered: true
            selected: true
            foreground: root.foreground
            background: root.surface
            accent: root.accent
            radius: root.radiusFor(Math.min(width, height))
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(12)
            onClicked: root.bar.startPluginJob(root.confirm.token)
          }
        }
      }
    }
  }

  // One catalogue entry: name and version, what it is doing, and its buttons
  // on the right with the primary one last.
  component EntryRow: Item {
    id: row
    property var view: ({})
    property int rowIndex: 0
    readonly property bool selected: root.selectedIndex === rowIndex
    width: list.width
    height: Math.max(Style.space(50), texts.implicitHeight + Style.space(12))

    Rectangle {
      anchors.fill: parent
      radius: root.radiusFor(Math.min(width, height))
      color: row.selected ? root.selectedFill : "transparent"
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.selectedIndex = row.rowIndex
    }

    Column {
      id: texts
      x: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - actions.width - Style.space(24)
      spacing: Style.space(2)

      Row {
        spacing: Style.space(8)
        Text {
          textFormat: Text.PlainText
          text: String(row.view.name || "")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
        }
        Text {
          anchors.baseline: parent.children[0].baseline
          textFormat: Text.PlainText
          text: String(row.view.version || "")
          color: root.secondary
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        width: texts.width
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: String(row.view.words || "")
        color: root.secondary
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall

        // Busy: the words breathe while the job runs.
        SequentialAnimation on opacity {
          running: row.view.state === "busy"
          loops: Animation.Infinite
          alwaysRunToEnd: true
          NumberAnimation { to: 0.55; duration: 700; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
        }
      }
    }

    Row {
      id: actions
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Repeater {
        model: row.view.actions || []
        Button {
          required property var modelData
          text: modelData.label
          enabled: modelData.enabled
          opacity: enabled ? 1 : 0.35
          bordered: true
          selected: modelData.primary
          foreground: root.foreground
          background: root.surface
          accent: root.accent
          radius: root.radiusFor(Math.min(width, height))
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.space(7)
          onClicked: { root.selectedIndex = row.rowIndex; root.run(modelData.name) }
        }
      }
    }
  }
}
