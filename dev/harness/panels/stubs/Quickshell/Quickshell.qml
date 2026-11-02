pragma Singleton
import QtQuick

// Stands in for Quickshell's own module under qmltestrunner (the real one is
// built into the quickshell binary): the environment is a map the test sets,
// and a detached command is recorded, not run.
QtObject {
  property var vars: ({})
  property var exec: []
  function env(name) { return vars[name] === undefined ? null : vars[name] }
  function execDetached(argv) { exec = exec.concat([argv]) }
}
