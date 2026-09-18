import QtQuick
import Quickshell

// The notch, as one plugin sees it.
//
// This is the only notch object a plugin ever gets: its integration file, the
// panels that integration draws, and its bar widget all receive the same
// `notchHost`. It is scoped to that plugin -- every call is attributed to
// `pluginId`, and nothing here reaches the rest of the notch or another
// plugin's state.
//
// Everything a panel needs to look like part of the notch is here (colours,
// radius, font, motion), because a plugin may not pick its own
// (DESIGN-PHILOSOPHY.md §1, §2, §5). PLUGINS.md documents every member.
QtObject {
  id: host

  // Set by NotchPlatform; never by the plugin.
  property var bar: null
  property var platform: null
  required property string pluginId

  readonly property int contract: platform ? platform.contract : 0
  readonly property var features: platform ? platform.features : []

  // Is this notch alive and hosting integrations? False while it is being taken
  // apart, which is a plugin's cue to draw its own UI again.
  readonly property bool present: platform ? (platform.enabled && platform.present) : false
  readonly property bool accepted: platform ? platform.accepted(pluginId) : false
  readonly property string reason: platform ? platform.reasonFor(pluginId) : "unknown"
  readonly property string reasonDetail: platform ? platform.reasonDetailFor(pluginId) : ""
  // The bar is hidden (`omarchy toggle bar`): nothing of the notch is on screen.
  readonly property bool hidden: !!bar && bar.barHidden

  // --- the look of the notch ------------------------------------------------

  readonly property color color: bar ? bar.notchColor : "#000000"
  readonly property color foreground: bar ? bar.notchForeground : "#ffffff"
  readonly property color secondary: bar ? bar.notchSecondaryText : "#ebebf5"
  readonly property color accent: bar ? bar.notchAccent : "#ffffff"
  readonly property real radius: bar ? bar.notchRadius : 8
  readonly property string fontFamily: bar ? bar.fontFamily : ""
  readonly property real restHeight: bar ? bar.notchCompactHeight : 32
  readonly property real maxPanelWidth: platform ? platform.maxPanelWidth : 0
  readonly property real maxPanelHeight: platform ? platform.maxPanelHeight : 0

  // The notch's own radius, never bigger than half the thing it rounds.
  function radiusFor(size) { return bar ? bar.radiusFor(size) : Math.min(radius, size / 2) }

  // --- the motion of the notch ----------------------------------------------

  readonly property int growHeightMs: 350
  readonly property int growWidthDelayMs: 50
  readonly property int growWidthMs: 300
  readonly property int shrinkMs: 240
  readonly property int fadeInMs: 220
  readonly property int fadeOutMs: 90
  readonly property real springDamping: 0.72

  // --- panels ---------------------------------------------------------------

  readonly property bool panelOpen: platform ? platform.panelOpenFor(pluginId) : false
  readonly property string panelRoute: platform ? platform.panelRouteFor(pluginId) : ""
  readonly property string panelScreen: platform ? platform.panelScreenFor(pluginId) : ""

  // Open this plugin's panel inside the notch. `screenName` is the screen the
  // click came from -- a widget passes its injected `notchScreen`; "" means the
  // focused screen. Answers "opened", "closed" or "declined:<reason>", and only
  // "opened" means the notch is showing it, so anything else is the plugin's
  // cue to open its own UI instead.
  function openPanel(route, screenName) {
    if (!platform) return "declined:not-accepted"
    return platform.openPanelFor(pluginId, String(route || ""), String(screenName || ""))
  }

  function closePanel() {
    if (!platform) return "unknown"
    return platform.closePanelFor(pluginId)
  }

  // --- activities -----------------------------------------------------------

  // Ask the notch to show a line at rest. Answers "shown", "queued" or
  // "declined:<reason>".
  function claim(activity) {
    if (!platform) return "declined:not-accepted"
    return platform.claimFor(pluginId, activity)
  }

  function release(key) {
    if (!platform) return "unknown"
    return platform.releaseFor(pluginId, String(key || pluginId))
  }
}
