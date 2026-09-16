.pragma library

// A key press as a Hyprland key combination, for the settings' record
// buttons: modifiers first in a fixed order, then the key, joined by " + ",
// in the uppercase names Hyprland binds accept (e.g. "SUPER + ALT + N").
//
//   combo(key, modifiers) -> { combo, waiting, reason }
//     waiting: only modifiers are held so far -- keep listening
//     combo:   the finished combination, or "" when the key cannot be bound
//     reason:  why not, for the settings to show

var MODIFIERS = [
  { mask: 0x10000000, name: "SUPER" },  // Qt.MetaModifier
  { mask: 0x04000000, name: "CTRL" },   // Qt.ControlModifier
  { mask: 0x08000000, name: "ALT" },    // Qt.AltModifier
  { mask: 0x02000000, name: "SHIFT" }   // Qt.ShiftModifier
]

// Qt key codes that are modifiers themselves.
var MODIFIER_KEYS = [0x01000020, 0x01000021, 0x01000022, 0x01000023, 0x01000024, 0x01000053, 0x01000054, 0x01001103]

var NAMED = {
  0x20: "SPACE", 0x01000004: "RETURN", 0x01000005: "RETURN", 0x01000001: "TAB",
  0x01000007: "DELETE", 0x01000006: "INSERT", 0x01000010: "HOME", 0x01000011: "END",
  0x01000016: "PRIOR", 0x01000017: "NEXT",
  0x01000012: "LEFT", 0x01000013: "UP", 0x01000014: "RIGHT", 0x01000015: "DOWN",
  0x01000009: "PRINT", 0x2d: "MINUS", 0x3d: "EQUAL", 0x2c: "COMMA", 0x2e: "PERIOD",
  0x2f: "SLASH", 0x5c: "BACKSLASH", 0x3b: "SEMICOLON", 0x27: "APOSTROPHE", 0x60: "GRAVE",
  0x5b: "BRACKETLEFT", 0x5d: "BRACKETRIGHT"
}

var ESCAPE = 0x01000000
var BACKSPACE = 0x01000003

function keyName(key) {
  if (key >= 0x41 && key <= 0x5a) return String.fromCharCode(key)          // A-Z
  if (key >= 0x30 && key <= 0x39) return String.fromCharCode(key)          // 0-9
  if (key >= 0x01000030 && key <= 0x01000052) return "F" + (key - 0x01000030 + 1)  // F1-F35
  return NAMED[key] || ""
}

function combo(key, modifiers) {
  if (MODIFIER_KEYS.indexOf(key) !== -1) return { combo: "", waiting: true, reason: "" }
  var name = keyName(key)
  if (!name) return { combo: "", waiting: false, reason: "that key can't be bound" }
  var mods = []
  for (var i = 0; i < MODIFIERS.length; i++)
    if (modifiers & MODIFIERS[i].mask) mods.push(MODIFIERS[i].name)
  // A plain key or Shift+key would fire while typing anywhere; F-keys and
  // the like are fine alone.
  var needsModifier = !/^F\d+$/.test(name) && !(name === "PRINT")
  if (needsModifier && mods.filter(function(m) { return m !== "SHIFT" }).length === 0)
    return { combo: "", waiting: false, reason: "add SUPER, CTRL or ALT" }
  return { combo: mods.concat([name]).join(" + "), waiting: false, reason: "" }
}
