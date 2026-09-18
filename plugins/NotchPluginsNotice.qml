import QtQuick
import qs.Commons
import qs.Ui
import "../"
import "PluginsModel.js" as PluginsModel

// The plugin-job notice: a small card the resting notch pops down into while a
// plugin job from the Plugins page runs and once it has finished -- usually in
// a notch rebuilt by the reload the job caused (see Bar.qml, "plugins"). Same
// layout as the update notice (NotchUpdate.qml), on the notch's colour, text
// colours and radius.
//
//   running   "Installing Face ID…"
//   done      "Face ID installed"   2.0.4   [Open setup] [Enable] [Restart shell]; clears after
//             a few seconds when it offers none of them
//   failed    "Couldn't install Face ID"  the reason   [Dismiss]
//
// It never reopens the page: a panel takes keyboard focus, and a reload
// shouldn't steal it.
Item {
  id: root

  // The notch's Bar.qml root, and the BarPanel window it is drawn in.
  property var bar: null
  property var window: null
  // What to show; kept by the notch while it shrinks away.
  property string notice: ""

  readonly property var job: bar && bar.pluginsJob ? bar.pluginsJob : ({})
  readonly property var entry: bar ? bar.pluginsJobEntry : null
  readonly property color foreground: bar ? bar.notchForeground : "#ffffff"
  readonly property color secondary: bar ? bar.notchSecondaryText : Qt.rgba(235 / 255, 235 / 255, 245 / 255, 0.6)
  readonly property color accent: bar ? bar.notchAccent : "#ffffff"
  readonly property color surface: bar ? bar.notchColor : "#000000"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property real rowHeight: bar ? bar.notchCompactHeight : 32
  readonly property real padding: Style.space(14)
  readonly property real actionsHeight: Style.space(30)

  function radiusFor(size) { return bar ? bar.radiusFor(size) : Math.max(0, Math.min(10, size / 2)) }
  function shortSha(sha) { return String(sha || "").slice(0, 7) }

  readonly property string name: {
    var listed = bar && bar.pluginsCatalogue ? (bar.pluginsCatalogue.plugins || []) : []
    for (var i = 0; i < listed.length; i++) if (listed[i].id === job.id) return listed[i].name
    return entry && entry.name ? entry.name : String(job.id || "The plugin")
  }
  readonly property string action: String(job.action || "install")
  readonly property bool setupDue: !!entry && entry.enabled === true && (entry.setup === "needed" || entry.setup === "attention")
  readonly property bool canEnable: !!entry && entry.installed === true && entry.enabled !== true
  readonly property bool stopped: job.phase === "running"

  readonly property string title: notice === "running"
      ? (action === "update" ? "Updating " : action === "enable" ? "Turning on " : "Installing ") + name + "…"
    : notice === "done"
      ? name + (action === "update" ? " updated" : action === "enable" ? " turned on" : " installed")
    : notice === "failed"
      ? "Couldn't " + (action === "update" ? "update " : action === "enable" ? "turn on " : "install ") + name
    : ""
  readonly property string detail: notice === "done" ? (job.version ? String(job.version) : shortSha(job.to)) : ""
  readonly property string line: {
    if (notice === "running") {
      if (job.phase !== "running") return "Checking how it went…"
      switch (job.step) {
        case "installing": return "Downloading from GitHub…"
        case "updating": return "Fetching the update…"
        case "verifying": return "Checking what arrived…"
        case "enabling": return "Turning it on…"
        default: return "Checking GitHub…"
      }
    }
    if (notice === "done") {
      if (setupDue) return name + " needs setting up in its own panel."
      if (canEnable) return "It's installed but turned off."
      if (job.restartSuggested === true) return "Restart the shell to load every file."
      return job.to ? "Now at commit " + shortSha(job.to) + "." : ""
    }
    if (notice === "failed") {
      if (stopped) return PluginsModel.reasonWords("stopped", name)
      if (job.reason === "command" && job.message) return String(job.message)
      // A folder moved aside is named, for deleting by hand.
      if (job.movedTo) return PluginsModel.reasonWords(job.reason, name) + " Moved to " + String(job.movedTo) + "."
      return PluginsModel.reasonWords(job.reason, name)
    }
    return ""
  }

  implicitWidth: Style.space(380)
  implicitHeight: rowHeight + actionsHeight + padding

  // pluginsPress "notice:<button>" (dev/plugins.sh): the button's own click
  // handler, if it is on show.
  function press(name) {
    var buttons = { dismiss: dismissButton, enable: enableButton, setup: setupButton, restart: restartButton }
    var b = buttons[name]
    if (!b || !b.visible) return "no-such-button"
    b.clicked()
    return "ok"
  }

  // Title row, on the resting notch's own row.
  Item {
    x: root.padding
    width: root.width - 2 * root.padding
    height: root.rowHeight

    Text {
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

      // Running: the title breathes while the job runs.
      SequentialAnimation on opacity {
        running: root.notice === "running"
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

      NotchButton {
        id: dismissButton
        visible: root.notice === "failed" || (root.notice === "done" && (root.setupDue || root.canEnable || root.job.restartSuggested === true))
        text: "Dismiss"
        bordered: true
        foreground: root.foreground
        background: root.surface
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.space(10)
        onClicked: if (root.bar) root.bar.ackPluginJob()
      }

      NotchButton {
        id: restartButton
        visible: root.notice === "done" && root.job.restartSuggested === true
        text: "Restart shell"
        bordered: true
        foreground: root.foreground
        background: root.surface
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.space(10)
        onClicked: if (root.bar) root.bar.restartShellForPlugins()
      }

      NotchButton {
        id: enableButton
        visible: root.notice === "done" && root.canEnable
        text: "Enable"
        bordered: true
        selected: true
        foreground: root.foreground
        background: root.surface
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.space(12)
        // No ack first: the enable job replaces the status file anyway.
        onClicked: if (root.bar) root.bar.enablePlugin(root.job.id)
      }

      NotchButton {
        id: setupButton
        visible: root.notice === "done" && root.setupDue
        text: "Open setup"
        bordered: true
        selected: true
        foreground: root.foreground
        background: root.surface
        accent: root.accent
        radius: root.radiusFor(Math.min(width, height))
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        horizontalPadding: Style.space(12)
        onClicked: if (root.bar) { var id = root.job.id; root.bar.ackPluginJob(); root.bar.openPluginSetup(id) }
      }
    }
  }
}
