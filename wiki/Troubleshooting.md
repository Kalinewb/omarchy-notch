# Troubleshooting

What the notch's short messages mean, why they appear, and what to try. The notch keeps its own words to a line; the long form is here.

For anything the [Setup](Setup-points.md) page lists (a hidden bar, a companion that is off, a keybind clash), read the point's own section there. This page covers the messages of the Plugins page, the job lines of the Setup page, and a widget that loads empty.

## Plugins and their messages

A Plugins job (install, update, enable, remove) that fails leaves its reason in the row's state until you press **Dismiss**; a refusal is shown on the confirmation card. The reasons follow, with the words as the notch writes them. Where a message names the plugin it is about, the examples here use Face ID.

## The notch's plugin list is invalid

*Reason `catalogue`.* `plugins/catalogue.json` failed its checks, and the installer validates it on every call, so every Plugins action fails. It means the notch's own folder is damaged or edited. Update or reinstall the notch (`omarchy plugin update kalinewb.notch`).

## Can't install that plugin here

*Reason `denied`.* The plugin is on the catalogue's deny list (`graveklar.liquid-notifications`, and both Face lock clones, `graveklar.face-lock` and `kalinewb.face-lock`), or it is the notch itself. The notch never installs or changes these from the Plugins page. Older notches said *That plugin can't be installed from the notch.*

## That plugin isn't in the notch's list

*Reason `unknown-id`.* Only the three plugins in the catalogue (Face ID, Profiles, OLED Corners) can be acted on, and only by id: a request never carries a URL or a path. Anything else is refused.

## A test notch can't change plugins

*Reason `sandbox`.* A test hook (`NOTCH_PLUGINS_*`) was set without both `NOTCH_PLUGINS_DIR` and `NOTCH_PLUGINS_OMARCHY`, so a half-configured test can't mix stand-ins with your real plugins folder, and every command refuses. You will not see this on your own notch.

## The session is locked

*Reason `locked`.* A plugin job never runs while the session is locked, because changing a plugin reloads the shell. Unlock and press the button again.

## A plugin job or update is running

*Reason `busy`.* One job runs at a time, and none alongside the notch's own update. Wait for the running one to finish (its notice says which) and try again. Older notches said: *Another plugin job or a notch update is running.*

## The plugin isn't installed

*Reason `not-installed`.* An update, enable or remove was asked for a plugin whose folder is not in the plugins folder, usually because it was removed from outside the notch. Press Refresh on the Plugins page.

## The plugin is already installed

*Reason `already-installed`.* An install found the folder already there. Press Refresh; the row will now show it as installed.

## Not from git: reinstall to update

*Reason `not-git`.* The plugin's folder isn't a git checkout (for instance Face ID installed by its own `./install.sh`, which makes a copy), so the notch can't move it to the verified commit. Reinstall it from the Plugins page, or leave its updates to the script that installed it. Older notches said: *Face ID wasn't installed from git, so it can't update here.*

## The plugin was installed from somewhere else

*Reason `wrong-origin`.* The checkout's `origin` is not the catalogue's GitHub URL, so the notch won't fetch from or move it. The row reads *Installed from somewhere else* and offers only Remove.

## The plugin has local changes

*Reason `local-changes`.* The checkout has uncommitted edits, or it isn't behind the verified commit (its history differs), so an update would lose work or isn't a clean move forward. The row reads *Local edits* or *Differs from the verified version*; **Review in terminal** shows what is different. The notch will not update it. Commit or discard the edits, or remove the plugin and install it again.

## The plugin is busy: try again soon

*Reason `plugin-busy`.* The plugin says it is in the middle of something that an update would break: Face ID while its install is running, Profiles while a switch is pending. The row shows *Busy* and dims Update. Wait for it to finish and try again. Older notches said: *Face ID is busy. Try again when it has finished.*

## Notch updated: reopen this card

*Reason `changed`.* The notch was updated while the confirmation card was open, and the update moved the plugin's verified commit, so installing what the card showed would install a commit the notch no longer vouches for. Close the card and open it again. It also appears when GitHub no longer has the verified commit. Older notches said: *The notch was updated while this card was open. Open it again.*

## The verified commit isn't the plugin

*Reason `wrong-id`.* The manifest at the verified commit names a different plugin than the catalogue entry, or the installed folder's manifest no longer says what it should, so nothing was changed. Shown as *Verified commit isn't Face ID: nothing changed.* This is the notch refusing a bad pin; it clears when a notch update brings a corrected catalogue.

## The verified commit is a bar

*Reason `bar-kind`.* The commit declares itself a bar. The Plugins page installs no bars (a bar would replace the notch), so it refuses before touching your plugins folder. Shown as *Verified commit is a bar, not Face ID.*

## The plugin has its old name: update it

*Reason `renamed`.* An install was asked for a plugin whose old-named folder (for Face ID, `graveklar.face`) is still there. Update the old one instead; the update finishes the rename. See [Lock and Face](Lock-and-Face.md#the-rename-from-graveklarface).

## Rename unfinished: open Setup

*Reason `rename`.* The plugin was updated to its new version, but the step that moves it to its new name didn't finish. Open [Setup](Setup-points.md#face-ids-settings-use-its-old-name) and press Fix on *Face ID's settings use its old name*; its Undo puts the old name back. Older notches said: *Face ID was updated, but its rename didn't finish. Setup can finish it.*

## Verified plugin didn't validate: left alone

*Reason `invalid`.* After checking out the verified commit, `omarchy plugin validate` rejected it, so the notch put the checkout back where it was. Nothing has changed. Shown as *Verified Face ID didn't validate: left alone.*

## Newer than verified: left alone

*Reason `newer`.* The checkout is past the verified commit (a global `omarchy plugin update` moved it). The notch won't downgrade it and doesn't nag. The row reads *Newer than the verified version*. Older notches said: *Face ID is newer than the verified version, so it stays as it is.*

## Didn't start: another job may be running

*Reason `not-started`.* A launched job didn't write its status within 5 seconds. Most often another plugin job or a notch update holds the lock. Wait and try again.

## The command failed

*Reason `command`.* A step the installer ran (`omarchy plugin add`, `enable` or `remove`, or checking out the pin) failed. The notice shows the last line the command printed instead of this sentence when there is one. Try the command yourself from a terminal.

## Stopped without finishing

*Reason `stopped`.* The job was killed (TERM or INT), or its runner disappeared, before it wrote a result. A stopped job stops upstream's whole process group and removes its staging folder, so nothing half-installed remains. Press Refresh and see what state the plugin is in.

## Couldn't reach GitHub

*Reason `offline`.* Cloning or fetching the verified commit failed. Check the network and try again.

## Turn the plugin on first

*Reason `not-hosted`.* **Open setup** or **Remove...** hands off to the plugin's own panel in the running shell, and the shell has no such panel because the plugin is not turned on. Press **Enable**, which the row offers, then try again.

## Couldn't ask the shell

*Reason `not-running`.* The same hand-off couldn't reach the shell at all (it is not running, or `omarchy-shell` failed). Restart the shell and try again.

## Something went wrong

The fallback for a reason the notch has no sentence for. The plugin's `plugins-job.json` in `$XDG_RUNTIME_DIR/kalinewb.notch/` holds the reason and message.

## Setup and its messages

The Setup page shows one state line under a point while a job runs, and after it:

## Didn't work: nothing changed

A Fix failed or was rolled back and the job reported no message of its own. The files are as they were; the *Snapshots* fold shows the snapshot taken. Older notches said: *That didn't work. Nothing was changed.*

## Files changed since the fix

An Undo (Restore) found that a file the fix changed has been edited since, and refused. Choose **Restore anyway** (which first snapshots the current state) or, for a marked block the fix added, **Remove the notch's block** and keep your own edits. Older notches said: *Those files changed since the fix.* The terminal exits 3.

## Couldn't undo

*Couldn't undo: files changed.* is the Restore case above; with a message the line reads *Couldn't undo:* and the job's message.

## Job stopped: check Snapshots

The Setup job's process disappeared before it finished (two checks in a row found it gone). Look at the *Snapshots* fold: a snapshot may have been taken, and Restore puts the files back. Older notches said: *The job stopped before it finished. Check Snapshots.*

## The session is locked, so nothing ran

Setup does not run while the session is locked.

## Nothing to fix here

*Terminal and page.* The point was not in a fixable state when the Fix ran (the problem was already gone, or it never had a Fix). Older notches said: *There is nothing to fix: this isn't happening here.* Exit code 4.

## Hyprland has config errors: fix them first

Fixes that write a Hyprland file (the menu-key fix and the OLED Corners fix) refuse while `hyprctl configerrors` is not empty, because the result could not be verified. Fix the errors in your Hyprland config and try again. Older notches said: *Hyprland already reports config errors, so a fix couldn't be verified.*

## Couldn't apply: nothing changed

The fix could not be written; everything stays as it was. Older notches said: *Couldn't apply the fix. Nothing was changed.*

## Didn't take: put back

The fix ran but re-running the check showed the problem was still there, so the notch rolled the files back from the snapshot. Older notches said: *The fix didn't take. Everything was put back.*

## Notch block not found

*Remove the notch's block* was pressed, but the file no longer holds the notch's marked block (you removed or edited it). Older notches said: *Couldn't find the notch's block in the file.*

## Files differ: run Restore again

A Restore finished but the files did not come back byte for byte. Press Restore again. Older notches said: *The files didn't come back as they were; run Restore again.*

## Other Setup lines

*Couldn't take a snapshot.*, *Couldn't copy* and a file name and *Couldn't put the files back.* are the Fix or Restore failing at the step they name, with nothing half done. *(file names) changed after the fix.* is the message of a refused Restore.

## Widgets are empty after a reload

When `shell.json` or a plugin changes on disk, Omarchy reloads the bar. It can hand a third-party bar a widget catalogue that still refers to the previous load, which leaves widgets empty until the shell restarts. The notch checks for that 2.5 seconds after loading and, if any widget is empty, asks for one plugin rescan, which refreshes the catalogue. It does this at most once every 30 seconds. Changes made from the settings panel don't reload the bar. A widget that is still empty after that shows up in [Setup](Setup-points.md#a-widget-in-the-bar-is-empty), whose Fix restarts the shell.

## The notch is gone

If the bar is not there at all, the common causes are checked by Setup and work from a terminal when there is no notch to press a button in: the bar toggle is off (`omarchy-toggle-bar`), another bar is active (`omarchy plugin enable kalinewb.notch`), or the notch failed to load (`omarchy plugin validate ~/.config/omarchy/plugins/kalinewb.notch`). Run `~/.config/omarchy/plugins/kalinewb.notch/bin/notch-setup detect`; see [Setup points](Setup-points.md#from-a-terminal).
