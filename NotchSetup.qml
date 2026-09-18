import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Setup: what's stopping the notch from working the way you want, and where it
// is safe, a button that puts it right.
//
// A pure view over `bar.setup` (SetupService.qml). Nothing here runs a process:
// a Fix asks the service, the service starts bin/notch-setup detached, and the
// script is the only thing that changes anything. Every fix snapshots the files
// it touches first, and Snapshots below can put them back.
//
// It is reached from the settings header, or `omarchy-shell notch view setup`,
// and closes like the settings: Escape, ✕, or a click outside.
Item {
  id: root

  property var bar: null
  property real maxHeight: 600
  property real headerHeight: 32
  signal closeRequested()
  signal backRequested()
  signal pluginsRequested()

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
  readonly property var points: setup ? setup.points : []
  readonly property var job: setup ? (setup.job || {}) : ({})
  readonly property bool available: setup ? setup.enabled : false

  // Which row is unfolded, and which one is asking "are you sure?".
  property string openRow: ""
  property string confirmRow: ""
  property string confirmKind: ""   // "fix" | "restore" | "restore-force" | "restore-block" | "forget"
  property bool showSnapshots: false
  property bool showHealthy: false

  readonly property var attention: filterBySeverity(["fix", "action"])
  readonly property var worthKnowing: filterBySeverity(["warn", "info", "unknown"])
  readonly property var healthy: filterBySeverity(["ok"])

  function filterBySeverity(kinds) {
    var out = []
    for (var i = 0; i < points.length; i++) if (kinds.indexOf(points[i].severity) !== -1) out.push(points[i])
    return out
  }

  function severityMark(severity) {
    switch (severity) {
      case "fix": return "!"
      case "action": return "›"
      case "warn": return "!"
      case "unknown": return "?"
      case "info": return "i"
    }
    return "·"
  }

  // What the row says now: a job for this point outranks what detection found.
  function rowState(point) {
    var j = job || {}
    if (j.point !== point.id) return ""
    if (j.phase === "done") return "fixed"
    if (j.phase === "failed" || j.phase === "rolled-back") return "failed"
    if (j.phase === "conflict") return "conflict"
    if (j.phase === "locked-out") return "locked"
    if (j.phase) return "working"
    return ""
  }

  function act(point) {
    if (point.handoff && point.handoff.view) {
      root.bar.focusedNotchWindow().openView(point.handoff.view, "setup")
      return
    }
    if (point.handoff && point.handoff.argv) {
      Quickshell.execDetached(point.handoff.argv)
      root.closeRequested()
      return
    }
    root.confirmRow = point.id
    root.confirmKind = "fix"
    root.openRow = point.id
  }

  focus: true
  Keys.onEscapePressed: {
    if (root.confirmRow !== "") { root.confirmRow = ""; return }
    root.closeRequested()
  }

  // --- header ---------------------------------------------------------------

  Item {
    id: header
    x: root.padding
    width: parent.width - 2 * root.padding
    height: root.headerHeight

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "Setup"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      Button {
        foreground: root.foreground
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
        text: "‹ Settings"
        fontFamily: root.fontFamily
        horizontalPadding: Style.space(10)
        onClicked: root.backRequested()
      }

      // Installing a plugin is setup, so the Plugins page lives here.
      Button {
        foreground: root.foreground
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
        text: "Plugins"
        fontFamily: root.fontFamily
        horizontalPadding: Style.space(10)
        onClicked: root.pluginsRequested()
      }

      Button {
        foreground: root.foreground
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
        text: "✕"
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
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: column
      width: parent.width
      spacing: Style.space(2)

      // Not this notch's job (a test notch, or one that isn't hosted).
      Text {
        visible: !root.available
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Setup isn't available in this notch."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        bottomPadding: Style.space(8)
      }

      // The job that is running, or the one that just finished.
      JobRow { visible: root.available && (root.job.phase || "") !== "" }

      Heading { text: "Needs attention"; visible: root.attention.length > 0 }
      Repeater {
        model: root.attention
        PointRow { point: modelData }
      }

      Text {
        visible: root.available && root.attention.length === 0 && !root.checking
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Nothing needs attention."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        topPadding: Style.space(6)
        bottomPadding: Style.space(6)
      }

      Heading { text: "Worth knowing"; visible: root.worthKnowing.length > 0 }
      Repeater {
        model: root.worthKnowing
        PointRow { point: modelData }
      }

      // Folded: everything that is fine, and the snapshots.
      Fold {
        title: "All good (" + root.healthy.length + ")"
        open: root.showHealthy
        visible: root.healthy.length > 0
        onToggled: root.showHealthy = !root.showHealthy

        Repeater {
          model: root.showHealthy ? root.healthy : []
          Text {
            width: column.width
            wrapMode: Text.WordWrap
            text: "· " + modelData.title
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            topPadding: Style.space(2)
          }
        }
      }

      Fold {
        title: "Snapshots (" + (root.setup ? root.setup.snapshots.length : 0) + ")"
        open: root.showSnapshots
        visible: root.setup && root.setup.snapshots.length > 0
        onToggled: { root.showSnapshots = !root.showSnapshots; if (root.showSnapshots && root.setup) root.setup.refreshSnapshots() }

        Repeater {
          model: root.showSnapshots && root.setup ? root.setup.snapshots : []
          SnapshotRow { snapshot: modelData }
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "From a terminal: notch-setup detect"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        topPadding: Style.space(10)
      }
    }
  }

  readonly property bool checking: setup ? setup.checking : false

  // --- pieces ---------------------------------------------------------------

  component Heading: Text {
    width: column.width
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    topPadding: Style.space(10)
    bottomPadding: Style.space(2)
  }

  // One detected point: a title, a line of explanation, and at most one button.
  // Clicking it unfolds what was found and which files a fix would touch.
  component PointRow: Column {
    id: pointRow
    property var point: ({})
    readonly property bool expanded: root.openRow === point.id
    readonly property bool confirming: root.confirmRow === point.id && root.confirmKind === "fix"
    readonly property string state_: root.rowState(point)
    readonly property bool fixable: point.fix && !(point.fix.disabledReason || "")

    width: column.width
    spacing: Style.space(2)
    topPadding: Style.space(4)
    bottomPadding: Style.space(4)

    Item {
      width: parent.width
      height: Math.max(Style.space(22), title.implicitHeight + summary.implicitHeight + Style.space(4))

      Text {
        id: mark
        text: root.severityMark(pointRow.point.severity)
        color: pointRow.point.severity === "fix" || pointRow.point.severity === "warn" ? root.accent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        width: Style.space(14)
      }

      Text {
        id: title
        anchors.left: mark.right
        anchors.right: action.left
        anchors.rightMargin: Style.space(8)
        anchors.top: parent.top
        text: pointRow.point.title || ""
        elide: Text.ElideRight
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        id: summary
        anchors.left: mark.right
        anchors.right: action.left
        anchors.rightMargin: Style.space(8)
        anchors.top: title.bottom
        text: {
          switch (pointRow.state_) {
            case "working": return "Fixing…"
            case "fixed": return "Fixed."
            case "failed": return String(root.job.message || "That didn't work. Nothing was changed.")
            case "conflict": return String(root.job.message || "Those files changed since the fix.")
            case "locked": return "The session is locked."
          }
          return pointRow.point.summary || ""
        }
        wrapMode: Text.WordWrap
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Button {
        id: action
        anchors.right: parent.right
        anchors.top: parent.top
        foreground: root.foreground
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
        fontFamily: root.fontFamily
        horizontalPadding: Style.space(10)
        visible: pointRow.state_ !== "working" && (pointRow.fixable || (pointRow.point.handoff && pointRow.point.handoff.label))
        enabled: root.available && !(root.setup && root.setup.jobRunning)
        text: {
          if (pointRow.state_ === "fixed") return "Undo"
          if (pointRow.point.handoff && pointRow.point.handoff.label) return pointRow.point.handoff.label
          return (pointRow.point.fix && pointRow.point.fix.label) || "Fix"
        }
        onClicked: {
          if (pointRow.state_ === "fixed") {
            root.confirmRow = pointRow.point.id
            root.confirmKind = "restore"
            root.openRow = pointRow.point.id
            return
          }
          root.act(pointRow.point)
        }
      }

      MouseArea {
        anchors.left: parent.left
        anchors.right: action.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openRow = pointRow.expanded ? "" : pointRow.point.id
      }
    }

    // The detail, and the confirmation, share one growing box: the panel
    // resizes on the notch's own timing rather than jumping.
    Item {
      width: parent.width
      clip: true
      height: pointRow.expanded ? detail.implicitHeight : 0
      Behavior on height { NumberAnimation { duration: pointRow.expanded ? 220 : 90; easing.type: Easing.OutCubic } }

      Column {
        id: detail
        width: parent.width
        spacing: Style.space(3)
        topPadding: Style.space(4)
        bottomPadding: Style.space(6)

        Repeater {
          model: pointRow.point.items || []
          Text {
            width: detail.width
            wrapMode: Text.WordWrap
            text: "• " + (modelData.summary || modelData.arg || "")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Repeater {
          model: pointRow.point.detail || []
          Text {
            width: detail.width
            wrapMode: Text.WordWrap
            text: String(modelData)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          visible: (pointRow.point.fix && (pointRow.point.fix.disabledReason || "")) !== ""
          width: detail.width
          wrapMode: Text.WordWrap
          text: pointRow.point.fix ? "No fix here: " + pointRow.point.fix.disabledReason : ""
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // Are you sure? Named files, and what is kept.
        Column {
          visible: pointRow.confirming || (root.confirmRow === pointRow.point.id && root.confirmKind === "restore")
          width: detail.width
          spacing: Style.space(4)
          topPadding: Style.space(4)

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: {
              if (root.confirmKind === "restore") return "Put the files back as they were before the fix."
              var files = (pointRow.point.fix && pointRow.point.fix.files) || []
              if (!files.length) return "Nothing on disk changes. A snapshot isn't needed."
              return "This changes " + files.join(", ") + ". A snapshot is taken first."
            }
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            spacing: Style.space(6)

            Button {
              foreground: root.foreground
              accent: root.accent
              radius: root.radiusFor(Math.min(width, height))
              text: "Cancel"
              fontFamily: root.fontFamily
              horizontalPadding: Style.space(10)
              onClicked: root.confirmRow = ""
            }

            Button {
              foreground: root.foreground
              accent: root.accent
              radius: root.radiusFor(Math.min(width, height))
              text: root.confirmKind === "restore" ? "Undo" : "Fix"
              fontFamily: root.fontFamily
              horizontalPadding: Style.space(10)
              onClicked: {
                if (root.confirmKind === "restore") {
                  var name = String(root.job.snapshot || "")
                  if (name) root.setup.startRestore(name, "")
                } else {
                  var arg = ""
                  var items = pointRow.point.items || []
                  if (items.length === 1) arg = String(items[0].arg || "")
                  root.setup.startFix(pointRow.point.id, arg)
                }
                root.confirmRow = ""
              }
            }
          }
        }
      }
    }
  }

  // A snapshot: when it was taken, what it was for, and the ways back.
  component SnapshotRow: Column {
    id: snapshotRow
    property var snapshot: ({})
    readonly property bool confirming: root.confirmRow === snapshot.name

    width: column.width
    spacing: Style.space(2)
    topPadding: Style.space(4)

    Item {
      width: parent.width
      height: Math.max(Style.space(20), snapTitle.implicitHeight + snapWhen.implicitHeight + Style.space(2))

      Text {
        id: snapTitle
        anchors.left: parent.left
        anchors.right: snapActions.left
        anchors.rightMargin: Style.space(8)
        anchors.top: parent.top
        text: snapshotRow.snapshot.title || snapshotRow.snapshot.point || ""
        elide: Text.ElideRight
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        id: snapWhen
        anchors.left: parent.left
        anchors.top: snapTitle.bottom
        text: {
          var at = Number(snapshotRow.snapshot.createdAt || 0)
          var when = at > 0 ? Qt.formatDateTime(new Date(at), "d MMM HH:mm") : ""
          var state = String(snapshotRow.snapshot.state || "")
          return when + (state ? " · " + state : "")
        }
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        id: snapActions
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(6)

        Button {
          foreground: root.foreground
          accent: root.accent
          radius: root.radiusFor(Math.min(width, height))
          text: "Restore"
          fontFamily: root.fontFamily
          horizontalPadding: Style.space(8)
          enabled: root.available && !(root.setup && root.setup.jobRunning)
          onClicked: { root.confirmRow = snapshotRow.snapshot.name; root.confirmKind = "restore" }
        }

        Button {
          foreground: root.foreground
          accent: root.accent
          radius: root.radiusFor(Math.min(width, height))
          text: "Delete"
          fontFamily: root.fontFamily
          horizontalPadding: Style.space(8)
          enabled: root.available
          onClicked: { root.confirmRow = snapshotRow.snapshot.name; root.confirmKind = "forget" }
        }
      }
    }

    Row {
      visible: snapshotRow.confirming
      spacing: Style.space(6)
      topPadding: Style.space(2)

      Button {
        foreground: root.foreground
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
        text: "Cancel"
        fontFamily: root.fontFamily
        horizontalPadding: Style.space(8)
        onClicked: root.confirmRow = ""
      }

      Button {
        foreground: root.foreground
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
        text: root.confirmKind === "forget" ? "Delete" : "Restore"
        fontFamily: root.fontFamily
        horizontalPadding: Style.space(8)
        onClicked: {
          if (root.confirmKind === "forget") root.setup.forget(snapshotRow.snapshot.name)
          else root.setup.startRestore(snapshotRow.snapshot.name, "")
          root.confirmRow = ""
        }
      }

      // Offered after a restore was refused because the file moved on.
      Button {
        visible: root.confirmKind === "restore" && (root.job.phase === "conflict")
          && String(root.job.snapshot || "") === snapshotRow.snapshot.name
        foreground: root.foreground
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
        text: snapshotRow.snapshot.block ? "Remove the notch's block" : "Restore anyway"
        fontFamily: root.fontFamily
        horizontalPadding: Style.space(8)
        onClicked: {
          root.setup.startRestore(snapshotRow.snapshot.name, snapshotRow.snapshot.block ? "block-only" : "force")
          root.confirmRow = ""
        }
      }
    }
  }

  // The job row: what is happening, or what happened.
  component JobRow: Item {
    width: column.width
    height: Math.max(Style.space(20), jobText.implicitHeight + Style.space(4))

    Text {
      id: jobText
      anchors.left: parent.left
      anchors.right: jobDismiss.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      wrapMode: Text.WordWrap
      text: {
        var j = root.job || {}
        var what = j.action === "restore" ? "Undo" : "Fix"
        switch (j.phase) {
          case "snapshotting": return what + ": taking a snapshot…"
          case "applying": return what + ": applying…"
          case "reloading": return what + ": reloading…"
          case "verifying": return what + ": checking…"
          case "done": return what + " done."
          case "conflict": return "Couldn't undo: " + String(j.message || "those files changed.")
          case "locked-out": return "The session is locked, so nothing ran."
          case "failed":
          case "rolled-back": return "Couldn't " + what.toLowerCase() + ": " + String(j.message || "it didn't take.")
        }
        return ""
      }
      color: (root.job.phase === "failed" || root.job.phase === "rolled-back" || root.job.phase === "conflict")
             ? root.accent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Button {
      id: jobDismiss
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      foreground: root.foreground
      accent: root.accent
      radius: root.radiusFor(Math.min(width, height))
      text: "Dismiss"
      fontFamily: root.fontFamily
      horizontalPadding: Style.space(8)
      visible: !(root.setup && root.setup.jobRunning) && (root.job.seen !== true)
      onClicked: root.setup.ack()
    }
  }

  // A folding group.
  component Fold: Column {
    id: fold
    property string title: ""
    property bool open: false
    signal toggled()
    default property alias content: foldSlot.data

    width: column.width
    spacing: Style.space(2)
    topPadding: Style.space(8)

    Item {
      width: parent.width
      height: Style.space(18)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: fold.title + (fold.open ? "  ▾" : "  ▸")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: fold.toggled()
      }
    }

    Item {
      width: parent.width
      clip: true
      height: fold.open ? foldSlot.childrenRect.height : 0
      Behavior on height { NumberAnimation { duration: fold.open ? 220 : 90; easing.type: Easing.OutCubic } }

      Column {
        id: foldSlot
        width: parent.width
        spacing: Style.space(2)
      }
    }
  }
}
