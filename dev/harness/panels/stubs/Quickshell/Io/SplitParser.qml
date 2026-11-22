import QtQuick

// Inert, like Process: InputDevices (a Commons singleton) hangs one on its watcher.
QtObject {
  property string splitMarker: "\n"
  signal read(string data)
}
