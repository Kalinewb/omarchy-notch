pragma Singleton
import QtQuick

// How the overlay companions find the notch, inside one shell process.
//
// The same arrangement as NotchMenuBridge and NotchOsdBridge, and separate from
// them for the same reason: each companion gets a narrow API of its own and none
// can reach another's. These companions (kalinewb.notch-clipboard, -emojis,
// -image-picker, -reminders: each `clonedFrom` the Omarchy picker of that name)
// share this one bridge, because they ask the notch the same four questions.
//
// `target` is deliberately not the notch's Bar root: it is the overlay api in
// Bar.qml, which can say whether the notch wants a picker, hold the picker's
// window down, take its card, and hear that the picker closed itself.
QtObject {
  // Bumped when that api's shape changes. A companion refuses a mismatch and
  // lets Omarchy's own picker open in its own window. Singleton code is cached
  // for the life of the shell process, so a change needs a shell restart
  // (install.sh does one).
  readonly property int apiVersion: 1

  // The overlay api (Bar.qml), while a notch is running here.
  property var target: null

  // Each loaded companion's go-between, by the Omarchy id it stands in for. The
  // notch asks this for each one's version and route, as it does of the others'
  // single `facade`.
  property var facades: ({})

  function register(id, facade) {
    var next = ({})
    for (var key in facades) next[key] = facades[key]
    next[String(id)] = facade
    facades = next
  }

  function unregister(id, facade) {
    if (facades[String(id)] !== facade) return
    var next = ({})
    for (var key in facades) if (key !== String(id)) next[key] = facades[key]
    facades = next
  }
}
