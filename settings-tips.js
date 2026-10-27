.pragma library

// The settings panel's one-line tips, shown under the panel while a row is
// hovered or focused: `Tips.t.<row id>`. Each is at most 60 characters, one
// sentence with no full stop, starts with what changes, and neither contains
// nor starts with the row's label. dev/settings.sh holds them to that.

var t = {
  atRest:        "Puts the clock or the playing track on the resting notch",
  autoHide:      "Tucks the notch into the edge; windows then use the top",
  openWith:      "Hover or click to expand; dimmed gestures are taken",
  opensTo:       "Shows this first when a click or keybind opens it",
  notifications: "Shows each in the notch; Notch only hides the toast too",
  notifyLight:   "Lights the screen edge while a notification shows",
  menu:          "Installs a helper so Omarchy's launcher opens in the notch",
  volume:        "Installs a helper so level changes show in the notch",
  glow:          "Lights the notch's edge while charging, around or under it",
  width:         "Widens the resting notch to fit what it shows",
  onHover:       "Previews these items without opening the notch",
  hidden:        "Leaves these widgets out of the open notch's row",
  panels:        "Opens these widgets' pop-ups in the notch, not a window",
  peeks:         "Widens the notch for a few seconds on a track or a charger",
  notifyTime:    "Closes each notification by itself, or waits until you act",
  lightColours:  "Aurora blends blue, white and purple; the others stay calm",
  windowsToTop:  "Lets windows reach the top edge, behind the notch",
  corners:       "Rounds the notch's lower edge, buttons and side curves",
  openRow:       "Adds time, date, media or battery beside the widgets",
  keybinds:      "Keys that open the notch or switch its modes from anywhere",
  stayOpen:      "Holds the notch open whatever the pointer does",
  glowSize:      "Sets how far the glow reaches, up to 80 px",
  greenAbove:    "Turns the glow green while charging at or above this",
  lowBelow:      "Switches the glow and peek to low under this level",
  updateCheck:   "Asks GitHub now and then if a new version exists",
  share:         "Copies your settings as a code, or saves a file",
  importer:      "Shows what a pasted code would change, then asks",
  reset:         "Erases every notch setting and returns the defaults"
}

// The `bar.notch` keys with no row in the panel: six whose default is the
// design (still read, still settable with `omarchy-shell notch set`) and
// eleven that never had one. dev/settings.sh checks these and the rows' keys
// together against every key the notch reads.
var noRow = [
  "settingsWith", "menuWith", "menuKey", "stateKey", "compactHeight", "criticalBattery",
  "color", "foreground", "chargingColor", "fullColor", "lowColor",
  "hoverDelay", "collapseDelay", "peekDuration",
  "hoverAction", "hoverPlugin", "expandOn"
]
