.pragma library

// What the notch knows about panels it draws for other people's widgets and cannot fix.
//
// The host moves every hosted panel's content below the back strip's zone, so a title or a chip row
// is never under it (Bar.qml `notchHostedTopInset`). What it cannot do is edit the panel: a
// "Back" button the plugin draws, or a pair of chevrons that read like one, stay. Settings →
// Integrations says so beside the name, so opting in is an informed choice. SURFACE-HOSTING.md section 15
// lists them with the rest of what is not hostable.
var NOTES = {
  "omaplug": "has its own Back buttons on two pages",
  "joramser.camera-test": "its ‹ › switch camera, not page"
}

function note(id) { return NOTES[String(id)] || "" }

// The label Settings shows for a hostable widget.
function label(id, name) {
  var n = note(id)
  return n ? name + " · " + n : name
}
