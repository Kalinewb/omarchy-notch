pragma Singleton
import QtQuick

// Stands in for Quickshell.Services.Pipewire, which Commons/UntypedInput (a
// Style dependency since Omarchy 4.5) reads the default input from: none here.
QtObject {
  property var defaultAudioSource: null
}
