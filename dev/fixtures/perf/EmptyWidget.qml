import QtQuick

// A bar widget that does nothing at all, for the dev/perf.sh scenarios that
// measure the notch without a plugin in the row. The media harness always puts
// one widget in the layout; this is what it puts there when the scenario is
// about the notch itself.
Item {
  property var bar: null
  property string moduleName: ""
  property var settings: ({})
  implicitWidth: 8
  implicitHeight: 8
}
