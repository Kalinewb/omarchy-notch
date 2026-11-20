.pragma library

// What the notch knows about panels it draws for other people's widgets and cannot fix.
//
// The host does not move a hosted panel to make room for the back strip: the strip is a zone at the
// top CENTRE (SURFACE-HOSTING.md section 15) and a panel keeps it clear by its own layout. The host
// cannot edit someone else's panel, so a panel that centres a title or a row there is pressed through
// by the strip, and a "Back" button the plugin draws, or chevrons that read like one, stay.
// Settings → Integrations says so beside the name, so opting in is an informed choice.
var NOTES = {
  "omaplug": "has its own Back buttons on two pages",
  "joramser.camera-test": "its ‹ › switch camera, not page",
  "omarchy.elsewhen": "its centred heading sits under the back zone",
  "io.github.thisisgm.omapods": "its centred title sits under the back zone",
  "io.github.therealasclepius.touchpad-comfortable": "its device chips run under the back zone"
}

function note(id) { return NOTES[String(id)] || "" }

// The label Settings shows for a hostable widget.
function label(id, name) {
  var n = note(id)
  return n ? name + " · " + n : name
}
