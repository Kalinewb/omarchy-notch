import QtQuick

// Quickshell's Singleton: a plain object that a `pragma Singleton` file roots
// itself in (Omarchy's Commons do, a Process or a Timer among their children).
QtObject {
  default property list<QtObject> data
}
