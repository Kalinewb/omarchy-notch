import QtQuick

// What this plugin gives the notch. It exists once, however many monitors
// there are, so anything with a cost (files, processes) belongs here rather
// than in the panel.
Item {
  id: integration

  // The notch sets this. Until it does, there is no notch.
  property var surfaceHost: null
  // Say false to decline for now; the notch shows the reason and the plugin
  // keeps its own UI.
  property bool available: true

  // The panel the notch draws. One instance per screen, from this one Component.
  property Component panel: Component { DemoPanel {} }

  // Named rows for activities this plugin claims.
  property var activityViews: ({ "progress": progressRow })
  property Component progressRow: Component { Item {} }
}
