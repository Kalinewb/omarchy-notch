# Lock and Face

Face ID is a separate plugin that lets you approve `sudo` (and, if you turn it on, the lock screen) by looking at your laptop. The notch installs and updates it from the [Plugins](Plugins.md) page and watches over its rename in [Setup](Setup-points.md); everything about what Face ID does and how it is wired is in its own repository, [Kalinewb/omarchy-face](https://github.com/Kalinewb/omarchy-face), whose README is the authority. This page covers what the notch does with it.

## Face ID

The Plugins page lists it as **Face ID** (`kalinewb.face`) at the commit the marketplace verified (version 2.2.0 in this notch's catalogue). Per its README at that commit, your password always still works: if a face isn't recognised in a few seconds, the lid is closed or a call is using the camera, the password prompt appears as always. It is a convenience, not a security upgrade, and its README spells out what it is not.

## Installing it

Press **Install...** on the Face ID row, read the card, and confirm. The notch clones the verified commit, checks it and enables it; it then offers **Open setup**, which opens Face ID's own panel. Everything that needs your password happens there, never in the notch: per Face ID's README, its Setup has one **Install Face ID** button that asks for your password once, installs its system files and starts building the face engine. Per its README, Face ID wires `sudo` with its own marked block in `/etc/pam.d/sudo` when you turn its switch on; the notch itself never touches that file or any other root-owned file.

The Face ID row reads *Needs setup* or *Needs attention* when its own status says so, and the [Setup](Setup-points.md#face-id-isnt-installed) page has a matching row with **Open setup**.

## The lock screen

Face ID's lock screen support is a second plugin, which Face ID stages into your plugins folder by itself, so the Plugins page refuses both lock clone ids (`graveklar.face-lock` and `kalinewb.face-lock`): it never installs or updates them. Whether face unlock is on for the lock screen is Face ID's own setting. While the session is locked the notch will not start a plugin job.

## Removing it

The **Remove...** button on the Face ID row hands off to Face ID's own panel, which describes what would be taken off the machine and does it (Settings, then *Remove Face ID from this machine*, per the notch's catalogue). The notch does not remove it itself.

## The rename from graveklar.face

Face ID was `graveklar.face` and is `kalinewb.face` from 3.0.0. Until then:

- An installed `graveklar.face` counts as Face ID, and Setup reads *Face ID will be renamed soon*: nothing to do.
- The row says *Renames to kalinewb.face* when an update brings the new name. Its card warns *Renames Face ID: asks a password later.*
- An update that brings the new name runs Face's own `bin/omarchy-face-rename --finish` through Setup, inside the notch's snapshot, so Undo puts the old name back. The shell restarts to load it, and Face ID's Setup then asks for your password once, to update its system files.
- If something was left half done, [Setup](Setup-points.md#face-ids-settings-use-its-old-name) shows *Face ID's settings use its old name* with a Fix that runs the same script.

A Face ID installed by its own `./install.sh` is a copy, not a checkout: the notch shows it as *Installed from somewhere else* and leaves its updates to that script.
