import QtQuick
import qs.Commons
import qs.Ui

// The update notice: a small card the resting notch pops down into when a
// notch update is out, while it installs, and once it has (see Bar.qml,
// "updates"). The notch grows around it -- same surface, top edge on the
// screen edge -- on the notch's colour, text colours and radius
// (DESIGN-PHILOSOPHY.md).
//
//   available   "Notch update"     0.1.0 → 0.2.0    [Later] [Update]
//   updating    "Updating Notch…"  the shell restarts when it's done
//   done        "Notch updated"    shown for a few seconds
//   failed      "Update failed"    the reason          [Dismiss]
Item {
  id: root

  // The notch's Bar.qml root.
  property var bar: null
  // What to show; kept by the notch while it shrinks away.
  property string notice: ""

  readonly property var check: bar && bar.updateCheckResult ? bar.updateCheckResult : ({})
  readonly property var job: bar && bar.updateJob ? bar.updateJob : ({})
  readonly property color foreground: bar ? bar.notchForeground : "#ffffff"
  readonly property color secondary: bar ? bar.notchSecondaryText : Qt.rgba(235 / 255, 235 / 255, 245 / 255, 0.6)
  readonly property color accent: bar ? bar.notchAccent : Color.accent
  readonly property color surface: bar ? bar.notchColor : "#000000"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property real rowHeight: bar ? bar.notchCompactHeight : 32
  readonly property real padding: Style.space(14)
  readonly property real actionsHeight: Style.space(30)

  // Whether Update takes a click (dev/plugins.sh).
  readonly property bool updateButtonEnabled: updateButton.enabled

  function radiusFor(size) { return bar ? bar.radiusFor(size) : Math.max(0, Math.min(10, size / 2)) }
  function shortSha(sha) { return String(sha || "").slice(0, 7) }

  readonly property string title: notice === "available" ? "Notch update"
    : notice === "updating" ? "Updating Notch…"
    : notice === "done" ? "Notch updated"
    : notice === "failed" ? "Update failed" : ""
  readonly property string detail: {
    if (notice === "available") {
      var from = String(check.localVersion || ""), to = String(check.remoteVersion || "")
      if (from && to && from !== to) return from + " → " + to
      var n = Number(check.behind || 0)
      return n === 1 ? "1 change" : n + " changes"
    }
    if (notice === "done") return job.version ? String(job.version) : shortSha(job.to)
    return ""
  }
  readonly property string line: notice === "available" ? String(check.subject || "")
    : notice === "updating" ? "The shell restarts when it's done."
    : notice === "done" ? (job.message ? String(job.message) : "Now running " + shortSha(job.to) + ".")
    : notice === "failed" ? String(job.message || "Something went wrong.") : ""

  implicitWidth: Style.space(360)
  implicitHeight: rowHeight + actionsHeight + padding

  // Title row, on the resting notch's own row.
  Item {
    id: titleRow
    x: root.padding
    width: root.width - 2 * root.padding
    height: root.rowHeight

    Text {
      id: titleText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, parent.width - detailText.implicitWidth - Style.space(12))
      textFormat: Text.PlainText
      text: root.title
      elide: Text.ElideRight
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.weight: Font.DemiBold

      // Updating: the title breathes while the job runs.
      SequentialAnimation on opacity {
        running: root.notice === "updating"
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { to: 0.55; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
      }
    }

    Text {
      id: detailText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.detail
      color: root.secondary
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // Detail line and actions.
  Item {
    x: root.padding
    y: root.rowHeight
    width: root.width - 2 * root.padding
    height: root.actionsHeight

    Text {
      anchors.left: parent.left
      anchors.right: actions.left
      anchors.rightMargin: actions.width > 0 ? Style.space(12) : 0
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.line
      elide: Text.ElideRight
      color: root.secondary
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Row {
      id: actions
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      Button {
        id: laterButton
        visible: root.notice === "available"
        text: "Later"
        bordered: true
        foreground: root.foreground
        background: root.surface
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.space(10)
        onClicked: if (root.bar) root.bar.snoozeUpdate()
      }

      Button {
        id: updateButton
        visible: root.notice === "available"
        // Not while a plugin job runs: both reload every plugin.
        enabled: !!root.bar && !root.bar.pluginJobRunning
        opacity: enabled ? 1 : 0.35
        text: "Update"
        bordered: true
        selected: true
        foreground: root.foreground
        background: root.surface
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.space(12)
        onClicked: if (root.bar) root.bar.startUpdate()
      }

      Button {
        visible: root.notice === "failed"
        text: "Dismiss"
        bordered: true
        foreground: root.foreground
        background: root.surface
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.space(10)
        onClicked: if (root.bar) root.bar.ackUpdate()
      }
    }
  }
}
