pragma Singleton
import QtQuick

// Stands in for Quickshell.Hyprland, which Commons/Style listens to for a
// config reload: no events here, and no monitors.
QtObject {
  signal rawEvent(var event)
}
