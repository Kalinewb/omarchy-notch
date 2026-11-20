import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Needs attention (the IPC view is still `setup`): what's stopping the notch
// from working the way you want, and where it is safe, a button that puts it right.
//
// A pure view over `bar.setup` (SetupService.qml). Nothing here runs a process:
// a button asks the service, the service starts bin/notch-setup detached, and
// the script is the only thing that changes anything. Every fix snapshots the
// files it touches first, and Earlier fixes below can put them back.
//
// A row is a title, one dim line and one button. A healthy machine has no rows
// at all: one calm line. The page is reached from the Settings header (shown
// only while something needs attention), from Settings > Advanced > Check for
// problems, or `omarchy-shell notch view setup`, and closes like the settings:
// Escape, the strip at the top centre, or a click outside.
Item {
  id: root

  property var bar: null
  property real maxHeight: 600
  property real headerHeight: 32
  signal closeRequested()

  readonly property real padding: Style.space(16)
  implicitWidth: Style.space(400)
  implicitHeight: Math.min(maxHeight, headerHeight + column.implicitHeight + padding)

  readonly property color foreground: bar ? bar.notchForeground : "#ffffff"
  readonly property color accent: bar ? bar.notchAccent : "#ffffff"
  readonly property color surface: bar ? bar.notchColor : "#000000"
  readonly property color dim: bar ? bar.notchSecondaryText : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.6)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  function radiusFor(size) { return bar ? bar.radiusFor(size) : Math.min(8, size / 2) }

  readonly property var setup: bar ? bar.setup : null
  // Reduced motion: the earlier fixes open in one cut.
  readonly property bool still: !!bar && bar.reducedMotion
  readonly property var job: setup ? (setup.job || {}) : ({})
  readonly property bool checking: setup ? setup.checking : false
  readonly property bool checkFailed: setup ? setup.checkFailed : false
  // "Checking…" only when it takes longer than a blink.
  property bool slow: false
  Timer {
    interval: 300
    running: root.checking
    onRunningChanged: if (!running) root.slow = false
    onTriggered: root.slow = true
  }

  // Points the page lists: the ones that need attention, plus a row just fixed
  // that has since healed, so its Undo stays in reach until the page closes.
  property var remembered: ({})
  function remember(point) { var copy = Object.assign({}, remembered); copy[point.id] = point; remembered = copy }
  readonly property var attention: {
    var out = []
    var list = setup ? setup.points : []
    for (var i = 0; i < list.length; i++) if (["fix", "action", "warn"].indexOf(list[i].severity) !== -1) out.push(list[i])
    var gone = remembered[job.point || ""]
    if (gone && job.phase === "done" && job.action === "fix" && !out.some(function(p) { return p.id === gone.id })) out.push(gone)
    return out
  }

  // The fixes that can still be undone.
  readonly property var undoable: {
    var out = []
    var list = setup ? setup.snapshots : []
    for (var i = 0; i < list.length; i++) if (list[i].state === "applied" || list[i].state === "verified") out.push(list[i])
    return out
  }

  property string confirmRow: ""
  onEnabledChanged: {
    if (enabled) { nav.reset(); return }
    confirmRow = ""
    remembered = ({})
    if (setup && (job.phase === "conflict" || job.phase === "failed" || job.phase === "rolled-back") && job.seen !== true) setup.ack()
  }

  // What a row says now: a job for it outranks what detection found.
  function rowState(point) {
    var j = job || {}
    if (j.point !== point.id || j.action !== "fix") return ""
    if (j.phase === "done") return "fixed"
    if (j.phase === "failed" || j.phase === "rolled-back") return j.seen === true ? "" : "failed"
    if (j.phase === "locked-out") return j.seen === true ? "" : "locked"
    if (j.phase) return "working"
    return ""
  }
  function snapshotState(snapshot) {
    var j = job || {}
    if (j.action !== "restore" || j.snapshot !== snapshot.name) return ""
    if (j.phase === "conflict") return j.seen === true ? "" : "conflict"
    if (j.phase === "failed" || j.phase === "rolled-back") return j.seen === true ? "" : "failed"
    if (j.phase === "done" || j.phase === "locked-out" || !j.phase) return ""
    return "working"
  }

  function fixNow(point) {
    var arg = ""
    var items = point.items || []
    if (items.length === 1) arg = String(items[0].arg || "")
    remember(point)
    setup.startFix(point.id, arg)
  }

  // One press does it. Only a fix that restarts the shell asks first, because
  // the notch closes for a moment.
  function act(point) {
    if (point.handoff && point.handoff.view) { root.bar.focusedNotchWindow().openView(point.handoff.view, "setup"); return }
    if (point.handoff && point.handoff.argv) { Quickshell.execDetached(point.handoff.argv); root.closeRequested(); return }
    if (point.handoff && point.handoff.helper) { setup.retryHelper(point.handoff.helper); return }
    if (point.fix && point.fix.destroysNotch) { confirmRow = point.id; return }
    fixNow(point)
  }

  // The keyboard: the row cursor of the Settings panel (NotchSettingsCursor.qml)
  // over the points and the earlier fixes. Up and Down move, Enter presses the
  // row's button, Left and Right walk the buttons, Escape closes a question, then the page.
  focus: true
  Keys.onPressed: function(event) { event.accepted = nav.handle(event) }
  NotchSettingsCursor { id: nav; panel: root; flick: flick }
  property var recorder: null
  function rows() { return groups.reduce(function(all, g) { return all.concat(g.rows()) }, []) }
  // A question waiting for its answer: Escape says no.
  function cancelPending() { var waiting = confirmRow !== ""; confirmRow = ""; return waiting }
  readonly property var groups: [needsStops, earlierFold]

  // The cursor asks the page's foot line for tips; this page has none.
  readonly property QtObject tip: QtObject {
    property bool pending: false
    property bool shown: false
    property real y: 0
    function hide() {}
    function leave() {}
    function want() {}
    function report() { return ({}) }
  }

  // --- header ---------------------------------------------------------------

  Item {
    id: header
    x: root.padding
    width: parent.width - 2 * root.padding
    height: root.headerHeight

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "Needs attention"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)
    }
  }

  Flickable {
    id: flick
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

      Repeater {
        id: needsList
        model: root.checkFailed ? [] : root.attention
        PointRow { point: modelData }
      }

      // Nothing to list: one calm line, or the honest account of why not.
      Column {
        visible: root.checkFailed || root.attention.length === 0
        width: parent.width
        spacing: Style.space(2)
        topPadding: Style.space(14)
        bottomPadding: Style.space(10)

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: root.checkFailed ? "Couldn't check." : root.checking && root.slow ? "Checking…" : root.checking ? "" : "Everything is working."
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          visible: !root.checkFailed && !root.checking
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "Checked just now."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Item {
          visible: root.checkFailed
          width: parent.width
          height: retryButton.height + Style.space(8)
          ActionButton {
            id: retryButton
            anchors.horizontalCenter: parent.horizontalCenter
            y: Style.space(8)
            text: "Try again"
            enabled: !root.checking
            onClicked: root.setup.check(false)
          }
        }
      }

      Fold {
        id: earlierFold
        rid: "earlier"
        title: "Earlier fixes (" + root.undoable.length + ")"
        visible: root.undoable.length > 0
        onOpenChanged: if (open && root.setup) root.setup.refreshSnapshots()
        rowsOf: function() { return root.itemsOf(snapList) }

        Repeater {
          id: snapList
          model: earlierFold.open ? root.undoable : []
          SnapshotRow { snapshot: modelData }
        }
      }
    }
  }

  // --- pieces ---------------------------------------------------------------

  function itemsOf(list) { var out = []; for (var i = 0; i < list.count; i++) out.push(list.itemAt(i)); return out }
  // A run of points, as the row cursor sees it.
  component Stops: QtObject {
    property Repeater list: null
    readonly property bool fold: false
    function rows() { return root.itemsOf(list) }
  }
  Stops { id: needsStops; list: needsList }

  component HeaderButton: NotchPanelButton { page: root; header: true }
  component ActionButton: NotchPanelButton { page: root }

  // One thing that needs attention: a title, a line, and at most one button.
  component PointRow: Column {
    id: pointRow
    property var point: ({})
    readonly property string state_: root.rowState(point)
    readonly property bool asking: root.confirmRow === point.id
    readonly property bool fixable: !!point.fix && !(point.fix.disabledReason || "")
    readonly property bool pressable: fixable || !!(point.handoff && (point.handoff.label || point.handoff.helper))

    // What the row cursor reads: a stop whose buttons are its lines.
    readonly property string rid: point.id
    readonly property string kind: "point"
    readonly property bool foldable: false
    readonly property Item head: line
    function targets() { return [cancelButton, action].filter(function(b) { return b.visible && b.enabled }) }
    Accessible.role: Accessible.ListItem
    Accessible.name: point.title || ""
    Accessible.description: sentence.text

    width: column.width
    topPadding: Style.space(4)
    bottomPadding: Style.space(4)

    Item {
      id: line
      width: parent.width
      height: Math.max(Style.space(26), title.implicitHeight + sentence.implicitHeight + Style.space(2))

      NotchCursorFill { page: root; visible: nav.at === pointRow.rid && nav.sub < 0 }
      HoverHandler { onHoveredChanged: hovered ? nav.hover(pointRow) : nav.unhover(pointRow) }

      Text {
        id: title
        anchors.left: parent.left
        anchors.right: buttons.left
        anchors.rightMargin: Style.space(8)
        anchors.top: parent.top
        text: pointRow.point.title || ""
        elide: Text.ElideRight
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        id: sentence
        anchors.left: parent.left
        anchors.right: buttons.left
        anchors.rightMargin: Style.space(8)
        anchors.top: title.bottom
        text: {
          if (pointRow.asking) return "This restarts the bar. The notch closes for a moment."
          switch (pointRow.state_) {
            case "working": return "Fixing…"
            case "fixed": return "Fixed."
            case "failed": return "Couldn't fix this. Nothing was changed."
            case "conflict": return "You changed that since. Undo anyway?"
            case "locked": return "The screen is locked. Try again after you unlock."
          }
          var reason = pointRow.point.fix ? String(pointRow.point.fix.disabledReason || "") : ""
          return reason !== "" ? "Paused: " + reason : pointRow.point.summary || ""
        }
        wrapMode: Text.WordWrap
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Row {
        id: buttons
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(6)

        ActionButton {
          id: cancelButton
          visible: pointRow.asking
          text: "Cancel"
          onClicked: root.confirmRow = ""
        }

        ActionButton {
          id: action
          visible: pointRow.state_ !== "working" && (pointRow.asking || pointRow.state_ !== "" || pointRow.pressable)
          enabled: !!root.setup && root.setup.enabled && !root.setup.jobRunning
          text: {
            if (pointRow.asking) return "Restart"
            switch (pointRow.state_) {
              case "fixed": return "Undo"
              case "failed":
              case "locked": return "Try again"
              case "conflict": return "Undo anyway"
            }
            if (pointRow.point.handoff && pointRow.point.handoff.label) return pointRow.point.handoff.label
            return (pointRow.point.fix && pointRow.point.fix.label) || "Fix"
          }
          onClicked: {
            switch (pointRow.state_) {
              case "fixed": root.setup.startRestore(String(root.job.snapshot || ""), ""); return
              case "conflict": root.setup.startRestore(String(root.job.snapshot || ""), "force"); return
              case "failed":
              case "locked": root.setup.ack()
            }
            if (pointRow.asking) { root.confirmRow = ""; root.fixNow(pointRow.point); return }
            root.act(pointRow.point)
          }
        }
      }
    }
  }

  // A fix that was made and can be put back: what it was, when, one Undo.
  component SnapshotRow: Column {
    id: snapshotRow
    property var snapshot: ({})
    readonly property string state_: root.snapshotState(snapshot)

    // What the row cursor reads: a stop whose buttons are its lines.
    readonly property string rid: snapshot.name || ""
    readonly property string kind: "snapshot"
    readonly property bool open: state_ === "conflict"
    readonly property Item head: snapLine
    function targets() { return [snapCancel, snapForce, snapUndo].filter(function(b) { return b.visible && b.enabled }) }
    Accessible.role: Accessible.ListItem
    Accessible.name: snapshot.title || ""
    Accessible.description: snapWhen.text

    width: column.width
    topPadding: Style.space(4)

    Item {
      id: snapLine
      width: parent.width
      height: Math.max(Style.space(24), snapTitle.implicitHeight + snapWhen.implicitHeight + Style.space(2))

      NotchCursorFill { page: root; visible: nav.at === snapshotRow.rid && nav.sub < 0 }

      Text {
        id: snapTitle
        anchors.left: parent.left
        anchors.right: snapActions.left
        anchors.rightMargin: Style.space(8)
        anchors.top: parent.top
        text: snapshotRow.snapshot.title || ""
        elide: Text.ElideRight
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        id: snapWhen
        anchors.left: parent.left
        anchors.right: snapActions.left
        anchors.rightMargin: Style.space(8)
        anchors.top: snapTitle.bottom
        wrapMode: Text.WordWrap
        text: {
          switch (snapshotRow.state_) {
            case "working": return "Undoing…"
            case "failed": return "Couldn't undo this. Nothing was changed."
            case "conflict": return "You edited that file since. Undo anyway?"
          }
          var at = Number(snapshotRow.snapshot.createdAt || 0)
          return at > 0 ? Qt.formatDateTime(new Date(at), "d MMM, HH:mm") : ""
        }
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Row {
        id: snapActions
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(6)

        ActionButton {
          id: snapCancel
          visible: snapshotRow.state_ === "conflict"
          text: "Cancel"
          onClicked: root.setup.ack()
        }

        // After an undo was refused because the file moved on.
        ActionButton {
          id: snapForce
          visible: snapshotRow.state_ === "conflict"
          text: snapshotRow.snapshot.block ? "Remove only what the notch added" : "Undo anyway"
          onClicked: root.setup.startRestore(snapshotRow.snapshot.name, snapshotRow.snapshot.block ? "block-only" : "force")
        }

        ActionButton {
          id: snapUndo
          visible: snapshotRow.state_ === "" || snapshotRow.state_ === "failed"
          text: snapshotRow.state_ === "failed" ? "Try again" : "Undo"
          enabled: !!root.setup && root.setup.enabled && !root.setup.jobRunning
          onClicked: { root.setup.ack(); root.setup.startRestore(snapshotRow.snapshot.name, "") }
        }
      }
    }
  }

  // A folding group: a stop of the row cursor that opens and closes the rows
  // under it (`rowsOf` lists them).
  component Fold: Column {
    id: foldBox
    property string rid: ""
    property string title: ""
    property bool open: false
    property var rowsOf: function() { return [] }
    readonly property bool fold: true
    readonly property string kind: "fold"
    readonly property Item head: foldHead
    default property alias content: foldSlot.data
    function rows() { return rowsOf() }

    width: column.width
    spacing: Style.space(2)
    topPadding: Style.space(8)

    Item {
      id: foldHead
      width: parent.width
      height: Style.space(18)
      Accessible.role: Accessible.Button
      Accessible.name: foldBox.title
      Accessible.expanded: foldBox.open
      Accessible.onPressAction: foldBox.open = !foldBox.open

      NotchCursorFill { page: root; visible: nav.at === foldBox.rid }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: foldBox.title + (foldBox.open ? "  ▾" : "  ▸")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: foldBox.open = !foldBox.open
      }
    }

    Item {
      width: parent.width
      clip: true
      height: foldBox.open ? foldSlot.childrenRect.height : 0
      Behavior on height { NumberAnimation { duration: root.still ? 0 : foldBox.open ? 220 : 90; easing.type: Easing.OutCubic } }

      Column {
        id: foldSlot
        width: parent.width
        spacing: Style.space(2)
      }
    }
  }
}
