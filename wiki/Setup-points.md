# Setup points

Setup is a list of things about this machine that stop the notch working the way you want, each in a line, with a **Fix** button where the notch can safely put it right.

Open it with the **Setup** button in [Settings](Settings.md#the-header) (the count beside it is the number of things that need attention), or directly with `omarchy-shell notch view setup`. `notch-setup detect` checks twenty-three things; the running notch adds one more (your theme's tokens) and answers two itself (empty widgets, and whether the menu companion loaded). Each row is a title and, when there is one, a state; rest the pointer on a row (or walk to it) and a one-line tip says what the finding is. Click a row and it unfolds what was found. The longer account of each point is below.

## The page

The header has **‹ Settings** (back), **Plugins** (installing a plugin is setup, so the [Plugins](Plugins.md) page opens from here) and ✕. The rows are in three groups:

- **Needs attention**: points with a Fix, points that ask you to do something (an *action*, such as *Open Plugins*), and warnings with no button because you wrote the thing yourself. The count on the Settings button is this group.
- **Worth knowing**: information, and checks that couldn't be made.
- **All good (n)**: a fold listing everything that is fine.
- **Nothing needs attention.** shows when the first group is empty. **Setup isn't available in this notch.** shows in a test notch or one that isn't hosted.

## Fix

**Nothing is done behind your back.** Fix unfolds a confirmation, *Changes* and the files it will change, with **Cancel** and **Fix**. A tip on the Fix button says that it snapshots those files first, then changes them (or that it changes nothing on disk, so there is no snapshot). Before it changes them the files are copied into `~/.local/state/kalinewb.notch/setup/snapshots/`. Whether a fix worked is decided by running the check again and hashing the files, never by a command's exit status: a fix that doesn't take is rolled back by itself, and the job row says *Didn't take: put back.*

A fix that restarts the shell shows **Restarts the shell: notch closes.** beside the button; the page comes back with the result.

While a job runs the page shows its step (*taking a snapshot...*, *applying...*, *reloading...*, *checking...*), then *Fix done.* or why not (see [Troubleshooting](Troubleshooting.md#setup-and-its-messages)). One setup job runs at a time, and none while the session is locked.

## Snapshots

**Snapshots (n)** at the bottom of the page lists them, each with when it was taken and its state. **Restore** puts a snapshot's files back byte for byte, after a confirmation (the button on the confirmation is **Undo**). A restore of a file you have edited since is refused and says so; you can then **Remove the notch's block** (when the fix added a marked block) and keep your own edits, or **Restore anyway**, which snapshots the current state first. **Delete** forgets a snapshot, and with it the way back; nothing a fix moved aside is deleted until you do.

## From a terminal

Some of what Setup finds means there is no notch to press a button in (the bar is hidden, the notch isn't the active bar, it failed to load), so all of it works from a terminal too:

```sh
~/.config/omarchy/plugins/kalinewb.notch/bin/notch-setup detect      # the same list, as a table
~/.config/omarchy/plugins/kalinewb.notch/bin/notch-setup fix <point>
~/.config/omarchy/plugins/kalinewb.notch/bin/notch-setup snapshots
~/.config/omarchy/plugins/kalinewb.notch/bin/notch-setup restore <snapshot>
```

`detect` only reads. It works out your effective keybinds by loading your Hyprland config with a recording stand-in for Hyprland's own `hl` table (the same trick Omarchy's keybindings menu uses), which is the only way to see a `code:` key or a bind written in Lua. Setup never runs anything privileged, never touches a plugin's own setup, and never writes the plugins folder, except that it moves the leftovers listed under *Old backup files* into a snapshot. `--json` prints the points as JSON, `--only <id>` checks one, `show <snapshot> --diff` shows what a snapshot holds, and `forget <snapshot>` is the terminal's Delete.

Exit codes of `fix` and `restore`: 0 done, 1 failed and rolled back, 2 usage or refused, 3 files changed since the fix, 4 not detected so nothing to fix, 5 another job holds the lock.

## The bar is hidden

*Point `bar-off`, needs attention.* Omarchy's bar toggle is off, so the notch isn't drawn at all. The flag is `~/.local/state/omarchy/toggles/bar-off`. Fix runs `omarchy-toggle-bar off`, which removes the flag and tells the bar to come back. The direction is inverted on purpose: `omarchy toggle bar on` is what hides it.

## Another bar is active

*Point `notch-not-bar`.* The active bar (`bar.id` in `shell.json`) isn't the notch, so the notch isn't showing. Fix runs `omarchy plugin enable kalinewb.notch`; Undo puts the other bar back. If the notch isn't in the plugins folder at all the point reads *The notch isn't installed here* (worth knowing), and *Couldn't read the active bar* means `shell.json` couldn't be read.

## The notch failed to load

*Point `notch-failed`, a warning.* The notch is the chosen bar, but the shell couldn't load it, so Omarchy fell back to another bar. Run `omarchy plugin validate ~/.config/omarchy/plugins/kalinewb.notch` to see why, then `./install.sh` from the dev checkout, or restart the shell. No Fix.

## Hyprland reports config errors

*Point `hypr-config-errors`, a warning.* `hyprctl configerrors` is not empty; the errors are listed under the row. While they are there, fixes that write Hyprland files are switched off, because none of them could be verified, and a Fix that would write one ends with *Hyprland has config errors: fix them first.*

## The menu companion is switched off

*Point `menu-replace-companion`.* While *Menu* is off in [Settings](Settings.md#menu) the point reads *Omarchy's own menu is in use*. With it on, depending on what it finds:

- **The menu companion is switched off.** `kalinewb.notch-menu` is disabled, so the menu still opens in Omarchy's own window. Fix runs `omarchy plugin enable kalinewb.notch-menu`; Undo runs `omarchy plugin disable kalinewb.notch-menu`, which puts `omarchy.menu` back exactly.
- **Removing the menu companion leaves no menu.** Omarchy brings `omarchy.menu` back only for a companion it has noted in `cloneSourceRestores`, and it hasn't noted this one. Fix adds the id to `shell.json`; Undo takes it out.
- **The menu companion isn't installed.** The notch installs it by itself and hasn't managed to. Switching *Menu* off and on again in Settings makes it try again; from a terminal, `bin/notch-companion install /dev/stdout`. The row's button is *Open Settings*.
- **Couldn't tell if the menu companion loaded** (worth knowing). Omarchy only builds a menu plugin's entry point while the menu is open, so from a terminal a working companion and a broken one look the same. Open the notch's menu: if it opens in the notch, it works. If it does not, run `omarchy plugin validate` on it and restart the shell. The running notch knows better than the script and replaces this verdict with *The menu opens in the notch* when its own bridge has the companion.

See [Menu](Menu.md#menu).

## The OSD companion is switched off

*Point `osd-companion`.* While *Volume and brightness* is off it reads *Omarchy's own OSD is in use*. With it on: **The OSD companion is switched off** (volume and brightness still show Omarchy's own card): Fix runs `omarchy plugin enable kalinewb.notch-osd`, Undo disables it. **Removing the OSD companion leaves no OSD**: same as the menu one, Fix notes `kalinewb.notch-osd` in `cloneSourceRestores`. **The OSD companion isn't installed**: the notch installs it by itself, and switching the setting off and on asks for another try. An Omarchy OSD call is answered by the notch, and by Omarchy's own card when the notch cannot show it: see [Notifications](Notifications.md#volume-and-brightness).

## The notifications companion is switched off

*Point `notifications-companion`.* While `suppressNativeToast` is off (*Notch + toast*) it reads *Omarchy's own toast is in use*. With it on (*Notch only*): **The notifications companion isn't running** (a warning): `kalinewb.notch-notifications` is enabled but not loaded, and it stands in for `omarchy.notifications`, so nothing may be showing notifications at all. `omarchy plugin validate` says why, and `omarchy plugin disable kalinewb.notch-notifications` puts `omarchy.notifications` back exactly. **The notifications companion is switched off**: Omarchy's toast still shows alongside the notch; Fix enables it. **The notifications companion isn't installed** (worth knowing): the notch installs it by itself. See [Notifications](Notifications.md#notifications).

## Menu keys skip the menu toggle

*Point `menu-keys-bypass`.* Some of your Hyprland keys that belong to Omarchy's menu family call the notch's menu directly, so *Menu* can't switch them back. Until the menu companion is set up the point only says so (*Menu keys call the notch directly*, worth knowing). Once it is, Fix appends a marked block to `~/.config/hypr/bindings.lua` that puts each key back on Omarchy's own default, which the companion then routes to the notch. Nothing in the block mentions the notch, so it keeps working if the notch is gone. Then `hyprctl reload` runs. If a key is bound in a file that loads after `bindings.lua`, Fix is disabled and names the file: change it there. *Couldn't read your keybinds* usually means `lua` isn't installed.

## A notch key is already taken

*Point `notch-key-collision`.* One of the notch's keys (`openKey`, `settingsKey`, `menuKey`, `autoHideKey`, `stayOpenKey`) is also used by another Hyprland bind, by another notch key, or (for `menuKey` with the menu replaced) by an Omarchy menu key, where one press would toggle the menu twice. Fix clears the notch's key in `shell.json`; your own bind is never touched. Set a different key in [Settings](Settings.md#keybinds) afterwards.

## Leftover notch keybinds

*Point `stale-notch-binds`.* Hyprland still has keybinds with a description starting *Notch* that no notch setting asks for (or which are bound twice, carry a test tag, or belong to a notch that isn't the active bar). Fix runs `hyprctl reload`, which drops every runtime bind; the notch adds its own back at once, and your monitor layout is re-applied by the same reload.

## The bar layout names a missing widget

*Point `layout-missing-plugin`.* A widget id in `bar.layout` isn't installed, or isn't a bar widget. Fix removes it from the layout with `omarchy plugin disable <id>`; Undo puts it back where it was.

## A widget in the bar is empty

*Point `layout-empty-widget`.* Only the running notch can see this, so the script's version just says *Only the notch can check this*. The notch lists widgets that loaded but drew nothing. Fix restarts the shell, which loads every plugin again; the notch closes while that happens and the page comes back with the result. See also [Troubleshooting](Troubleshooting.md#widgets-are-empty-after-a-reload).

## The notch's settings name a missing plugin

*Point `settings-stale-ids`.* One of `hoverPlugin`, `openPlugin`, `hoverPlugins`, `hiddenPlugins`, `hostedPanels` or Omarchy's `cloneSourceRestores` still names a plugin that isn't installed. The ids of the plugins the [Plugins](Plugins.md) page can install, and the names they had before, are never stale: a plugin you haven't installed yet keeps its entries. Fix rewrites each setting without those ids; Undo puts the old values back.

## Face ID isn't installed

*Point `plugin-face`; Profiles has the same shape as `plugin-profiles`.* One row per plugin the notch manages, with a button into the right page: **Open setup** when it is installed and enabled but says its own setup isn't finished, **Open Plugins** when it isn't installed, is switched off, or has a verified update ready. When all is well it reads *Face ID is set up* (in All good). *Couldn't check Face ID* means `bin/notch-plugins` didn't answer. See [Plugins](Plugins.md), [Lock and Face](Lock-and-Face.md) and [Profiles](Profiles.md).

## Face ID's settings use its old name

*Point `face-renamed`.* Face ID was `graveklar.face` and is `kalinewb.face` from 3.0.0. Before 3.0 an installed Face ID reads *Face ID will be renamed soon* (worth knowing; nothing to do until its 3.0 update). After, if a `graveklar.face` folder is still beside the new one, the new Face still sits in the old folder, or the bar or a saved profile still names the old id, Fix runs Face's own `omarchy-face-rename --finish`, which moves what is left to the new name and restarts the shell; Undo runs its `--rollback`, which puts everything back. See [Lock and Face](Lock-and-Face.md#the-rename-from-graveklarface).

## Profiles keybinds point at a missing script

*Point `profiles-binds-path`, a warning.* Keys in `~/.config/hypr/bindings.lua` call `plugins/kalinewb.profiles/bin/omarchy-profile`, which isn't there, so they do nothing. There is no Fix, because you wrote these binds: the notch only edits blocks it put there itself, and it cannot know what you meant by your own lines. Reinstall Profiles, which puts the script back, or delete the lines.

## A test notch is still running

*Point `stray-instances`.* Quickshell instances started from a temporary directory with `NOTCH_HARNESS=1` are left over from a check run. Fix kills only those. While a test run is in progress the point reads *Test shells are running* and asks for nothing.

## Old backup files in your config

*Point `stray-backups`.* Files like `bindings.lua.bak.1789067221` beside your Hyprland config, `shell.json.bak.<n>` beside `shell.json`, and plugin folders like `.kalinewb.notch-menu.bak.<time>` or `.notch-refused.<name>.<ms>` in the plugins folder. Some may be Omarchy's own: `omarchy-refresh-config` and `omarchy plugin remove` make the same kind. Fix moves them into a snapshot, so nothing is deleted until you Delete it, and Undo puts them back. Moving a folder out of the plugins folder reloads every plugin, so a fix that includes one restarts the notch.

## Omarchy changed upstream

*Point `upstream-drift`, worth knowing, for developers.* `dev/upstream/upstream.json` records the Omarchy version and a hash of each Omarchy file the notch was ported from. A file that changed, or a different Omarchy version, is listed with a `diff -u` to run. Only a developer needs to act on this.

## A layer rule animates the notch

*Point `layer-rules`, worth knowing.* Two cases: Omarchy's `no_anim` rule for the `omarchy-bar` layer isn't in effect (*The bar layer can animate*), so Hyprland may animate the notch's layer on top of its own animation; or a rule in your config asks for an animation on the notch's layers, which fights the notch's movement. No Fix.

## Corners pop in on screen change

*Point `oled-corners-still`.* Only checked when OLED Corners is installed. Hyprland animates a layer as it maps, and the corners' layers map again on every monitor change, so they fade in instead of just being there. Fix appends a marked block to `~/.config/hypr/looknfeel.lua` with Omarchy's own `no_anim=true` rule for `omarchy-oled-corners`, as OLED Corners' README suggests, then reloads. Nothing in the block mentions the notch. See [Corners](Corners.md).

## The notch can't update itself

*Point `notch-not-git`, worth knowing.* This copy isn't a git checkout, so it can't tell when a new version is out. Run `./install.sh --swap-to-git` once from the dev checkout. See [Plugins](Plugins.md#the-notch-itself).

## Your theme tints panels in the notch

*Added by the running notch.* A theme can pin selection, hover and focus fills in its style section (`selected-color = "accent"`, or a hex). A plugin panel the notch draws asks Omarchy's Style helpers for its fills, and a pinned token tells the helper to use the theme's colour instead of the notch's. These helpers are shared with the whole desktop, so the notch cannot override them for itself alone. Text is unaffected either way. Nothing to press. If it bothers you, set the tokens (`normal-color`, `hover-cursor-color`, `selected-color`, `pressed-color`, `focus-color`, `selection-color`) to `"foreground"` in the theme's `shell.toml` `[style]` section, or pick a theme that leaves them at the default; that changes them everywhere, not only in the notch. When nothing is pinned the point reads *Your theme doesn't tint the notch*. See also [Integrations](Integrations.md#colours).
