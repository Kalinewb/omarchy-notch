.pragma library

// The settings panel's one-line tips, shown under the panel while a row is
// hovered or focused: `Tips.t.<row id>`. Each is at most 60 characters, one
// sentence with no full stop, starts with what changes, never points at
// "this", "these", "those" or "each" (a tip stands alone), and neither contains
// nor starts with the row's label. dev/settings.sh holds them to that.

var t = {
  atRest:        "Puts the clock or the playing track on the resting notch",
  autoHide:      "Tucks the notch into the edge; windows then use the top",
  openWith:      "Chooses which gestures expand the notch",
  opensTo:       "Picks what shows first when you open the notch",
  notifications: "Shows alerts in the notch; Notch only hides Omarchy's own",
  notifyLight:   "Lights the screen edge while a notification shows",
  menu:          "Installs a helper so Omarchy's launcher opens in the notch",
  volume:        "Installs a helper so level changes show in the notch",
  glow:          "Lights the line under the notch while charging",
  width:         "Widens the resting notch to fit what it shows",
  onHover:       "Previews the chosen items without opening the notch",
  hidden:        "Leaves widgets out of the open notch's row",
  panels:        "Opens widgets' pop-ups in the notch, not a window",
  peeks:         "Widens the notch for a few seconds on a track or a charger",
  notifyTime:    "Closes a notification by itself, or waits until you act",
  lightColours:  "Aurora blends blue, white and purple; the others stay calm",
  windowsToTop:  "Lets windows reach the top edge, behind the notch",
  corners:       "Rounds the notch's lower edge, buttons and side curves",
  openRow:       "Adds time, date, media or battery beside the widgets",
  keybinds:      "Sets keys that open or switch the notch from anywhere",
  stayOpen:      "Holds the notch open whatever the pointer does",
  glowSize:      "Sets how far the glow reaches, up to 80 px",
  greenAbove:    "Turns the glow green once charge passes the level you set",
  lowBelow:      "Switches the glow and peek to low under the level you set",
  updateCheck:   "Asks GitHub now and then if a new version exists",
  problems:      "Shows what keeps the notch from working and how to fix it",
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
