import QtQuick
import Quickshell

// The one way the notch starts a job that has to outlive it.
//
// Updating the notch, installing a plugin, a companion or a Setup fix all
// change the plugins folder or restart the shell, and either destroys the notch
// that started the job. So every job runs detached, in its own transient
// `systemd-run --user` unit, and the rebuilt notch reads the job's status file
// to say how it went. Nothing else in the notch calls systemd-run.
//
//   launch(unitPrefix, run, envNames, modeEnv)
//     unitPrefix  the unit's name, before a timestamp ("kalinewb-notch-update")
//     run         the job's argv
//     envNames    the job's own variables (its test hooks), passed on when set
//     modeEnv     the variable a test sets to "setsid" for a plain detached child
//
// A transient unit starts from the user manager's environment, not the
// shell's, so it is handed what omarchy's commands need plus the job's own
// variables, and nothing else.
QtObject {
  readonly property var base: ["PATH", "HOME", "OMARCHY_PATH", "HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY",
                               "XDG_RUNTIME_DIR", "XDG_CONFIG_HOME", "XDG_STATE_HOME"]

  function argv(unitPrefix, run, envNames, modeEnv) {
    if ((Quickshell.env(modeEnv || "NOTCH_UPDATE_DETACH") || "systemd-run") !== "systemd-run") return ["setsid", "-f"].concat(run)
    var out = ["systemd-run", "--user", "--collect", "--quiet", "--unit", unitPrefix + "-" + Date.now()]
    var names = base.concat(envNames || [])
    for (var i = 0; i < names.length; i++) {
      var value = Quickshell.env(names[i])
      if (value) out.push("--setenv=" + names[i] + "=" + value)
    }
    return out.concat(run)
  }

  function launch(unitPrefix, run, envNames, modeEnv) {
    Quickshell.execDetached(argv(unitPrefix, run, envNames, modeEnv))
  }
}
