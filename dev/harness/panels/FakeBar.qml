import QtQuick

// The slice of Bar.qml the Settings, Setup and Plugins pages read, with the
// notch's defaults, and a record of what they write (dev/panels.sh). Not the
// notch: no window, no config file.
QtObject {
  id: bar

  readonly property color notchForeground: "#ffffff"
  readonly property color notchAccent: "#ffffff"
  readonly property color notchColor: "#000000"
  readonly property color notchSecondaryText: Qt.rgba(235 / 255, 235 / 255, 245 / 255, 0.6)
  readonly property string fontFamily: "sans-serif"
  function radiusFor(size) { return Math.max(0, Math.min(10, size / 2)) }

  // What the pages wrote.
  property bool reducedMotion: false
  property real notchCompactHeight: 32
  property var updateJob: ({})
  property var pluginsJob: ({})
  property var pluginsJobEntry: null
  property var writes: []
  property var config: ({ bar: { notch: { autoHide: true } } })
  property string batterySimulatedState: ""
  function setNotchSetting(key, value) { var o = {}; o[key] = value; return setNotchSettings(o) }
  function setNotchSettings(values) { writes = writes.concat([values]); return true }
  function notchSetting(key, fallback) { return fallback }
  property var shell: QtObject {
    function mutateShellConfig(fn) { fn(bar.config); bar.configEdits++ }
  }
  property int configEdits: 0

  property var notchCompactItems: []
  property bool notchAutoHide: false
  property bool notchBatteryGlow: true
  property string notchGlowStyle: "outline"
  property var notchOpenWith: ["hover", "click"]
  property var notchSettingsWith: []
  property var notchMenuWith: []
  property string notchOpenAction: "widgets"
  property string notchOpenPlugin: ""
  property bool notchNotifications: true
  property bool notchSuppressNativeToast: false
  property bool notchReplaceMenu: false
  property bool notchReplaceOsd: false
  property real notchCompactWidth: 180
  property var notchHoverItems: []
  property var notchHoverPlugins: []
  property var notchHiddenPlugins: []
  property var notchExpandedItems: []
  property real notchBottomRadius: 10
  property real notchFilletRadius: 10
  property bool notchNotificationStay: false
  property int notchNotificationSeconds: 6
  property bool notchPeekOnTrackChange: true
  property bool notchBatteryPeek: true
  property real notchGlowScale: 1
  property int notchGreenAbove: 100
  property int notchLowBattery: 20
  property string notchOpenKey: ""
  property string notchSettingsKey: ""
  property string notchAutoHideKey: ""
  property string notchStayOpenKey: ""
  property string notchMenuKey: ""
  property string notchStateKey: ""
  property bool notchStayOpen: false
  property bool notchWindowsToTop: false
  property bool notchUpdateCheck: true
  property var notchHostedPanels: []
  property var notchDisabledIntegrations: []
  property var notchPlugins: ({ list: [] })
  property var platform: ({ list: [] })
  property var updateCheckResult: ({ state: "none" })
  property var pluginsViews: []
  function layoutPluginChoices() { return [] }
  function hostableWidgets() { return [] }
  function releaseHostedPanel() {}
  function opensWith(gesture) { return notchOpenWith.indexOf(gesture) !== -1 }

  // Setup.
  property var setup: QtObject {
    property bool enabled: true
    property int issueCount: 0
    property var points: []
    property var job: ({})
    property bool jobRunning: false
    property var snapshots: []
    property bool checking: false
    property bool checkFailed: false
    property var calls: []
    function startFix(id, arg) { calls = calls.concat([["fix", id, arg]]) }
    function startRestore(name, mode) { calls = calls.concat([["restore", name, mode]]) }
    function forget(name) { calls = calls.concat([["forget", name]]) }
    function ack() { calls = calls.concat([["ack"]]) }
    function refreshSnapshots() {}
    function checkSoon() { calls = calls.concat([["soon"]]) }
    function check(localOnly) { calls = calls.concat([["check"]]) }
    function retryHelper(which) { calls = calls.concat([["helper", which]]) }
  }
  property var viewsOpened: []
  function focusedNotchWindow() { return { openView: function(view, from) { bar.viewsOpened = bar.viewsOpened.concat([[view, from]]) } } }

  // Plugins.
  property bool harnessed: true
  property var pluginsCatalogue: ({ plugins: [] })
  property var pluginsSelfView: ({ id: "kalinewb.notch", name: "Notch", version: "0.2.0", state: "ok", words: "Up to date", actions: [] })
  property var pluginsConfirm: ({})
  property var pluginsPreview: ({})
  property bool pluginsConfirmReady: false
  property var pluginsHandoff: null
  property bool pluginsCanAct: true
  property bool pluginsStateProcessRunning: false
  property bool pluginJobRunning: false
  property var pluginsState: ({})
  property var pluginCalls: []
  function refreshPluginsIfStale() {}
  function refreshPlugins() { pluginCalls = pluginCalls.concat(["refresh"]) }
  function askPluginAction(kind, id) { pluginCalls = pluginCalls.concat([kind + ":" + id]) }
  function cancelPluginAction() { pluginCalls = pluginCalls.concat(["cancel"]) }
  function startPluginJob(token) { pluginCalls = pluginCalls.concat(["job:" + token]) }
  function enablePlugin(id) { pluginCalls = pluginCalls.concat(["enable:" + id]) }
  function openPluginSetup(id) {}
  function openPluginRemoval(id) {}
  function reviewPluginInTerminal(id) {}
  function clearPluginHandoff() {}
  function ackPluginJob() {}
  function startUpdate() {}
  function checkForUpdates() {}
}
