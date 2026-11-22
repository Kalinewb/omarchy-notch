import QtQuick

// Inert: IpcRegistry (a Commons singleton) makes one to read the names a bare
// handler already has. Nothing here answers a call.
QtObject {
  property string target: ""
  property bool enabled: true
}
