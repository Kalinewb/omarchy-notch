# Plugins

The Plugins page installs, updates and removes the plugins the notch knows about, each at the commit the Omarchy plugin marketplace verified, and shows where the notch's own updates stand.

It opens from the **Updates** button in [Settings](Settings.md#the-header) or the **Plugins** button on the [Setup](Setup-points.md) page. Up and Down pick a row, Enter presses its main button, Escape closes. Over IPC it opens with `omarchy-shell notch plugins open`.

## What the page lists

**Face ID** (`kalinewb.face`, once `graveklar.face`), **Profiles** (`kalinewb.profiles`) and **OLED Corners** (`kalinewb.oled-corners`), then the notch itself. Only those three can be installed from here; `graveklar.liquid-notifications` and both Face lock clones (`graveklar.face-lock`, `kalinewb.face-lock`) are refused. Each is described on its own page: [Lock and Face](Lock-and-Face.md), [Profiles](Profiles.md), [Corners](Corners.md).

**Pinned, never HEAD.** `plugins/catalogue.json` names each plugin's GitHub URL and the full commit its marketplace listing verified. The page reads the plugins folder alone, with no network. So the suite updates when the notch does: a notch update can bring new pins, and each plugin then moves to its new pin on Update, and never past it.

## Refresh

The button beside the title (it reads *Checking...* while it works). Nothing is checked at startup: the page checks when it opens, on Refresh (not while a job runs), and after a job.

## Back to Setup

The **‹ Setup** button goes back to the [Setup page](Setup-points.md). ✕ closes the panel.

## Not installed

The row's state for a plugin that is not in your plugins folder. Its button is **Install...**.

## Pinned to the verified version

The checkout is at exactly the commit the catalogue names. The button is **Remove...**.

## Verified update ready

The notch has moved the pin on, so the checkout is behind it. Buttons: **Update to** and a version, such as *Update to 1.4.0...* (just **Update...** when the catalogue names no version) and **Remove...**. The state adds *Renames to* and the new id when the update brings a new name (see [Lock and Face](Lock-and-Face.md#the-rename-from-graveklarface)) and *Busy* when the plugin says it is busy, in which case Update is dimmed.

## Newer than the verified version

The checkout has been moved past the pin some other way, for instance by a global `omarchy plugin update`. The notch leaves it alone rather than nag or downgrade. Only **Remove...** is offered.

## Installed, turned off

The plugin is installed but not enabled. The state can add *Verified update ready* and *Turn on to set up*. **Enable** is the main button; the update button is offered beside it when an update is ready.

## Local edits

The checkout has uncommitted edits (*Local edits*), or its history differs from the verified one (*Differs from the verified version*). **Review in terminal** opens a floating terminal with the local edits and history; **Remove...** is also offered. Nothing here updates it.

## Installed from somewhere else

The folder is not a git checkout, or its `origin` is not the catalogue's URL. A Face ID installed by its own `./install.sh` is a copy, not a checkout, and reads like this; the notch leaves its updates to that script. Only **Remove...** is offered.

## Needs setup

An enabled plugin that says it needs setting up shows *Needs setup* or *Needs attention*, and **Open setup** becomes its main button. It opens the plugin's own panel; setup and removal of Face ID and Profiles happen in their own panels, because anything that needs your password does. Nothing in the notch asks for your password.

## Install...

Install, Update and Remove never run straight away: the page turns into a confirmation card. For an install the card shows the repository and the verified version and commit, and says *Plugins run unsandboxed inside your shell.* Hover **Install** and the tip says it installs the commit the marketplace verified.

An install clones the repository into a scratch folder outside the plugins folder, checks the pin out there, reads the manifest at the pin with `git show` (nothing in the clone is ever run), and hands that folder to `omarchy plugin add` as a local path. A pin whose manifest isn't the plugin, or is a bar, is refused before the plugins folder is touched. What lands is verified again, and then enabled; a folder that fails is moved aside to `plugins/.notch-refused.<name>.<ms>`, which Omarchy ignores. If the shell has not seen the new plugin within 10 seconds, it is left installed and turned off.

## Update to a version

The card says what the update brings: the number of commits, files and lines, up to five commit subjects, and the warnings that apply. *Updating closes the plugin's panel* if it is open, *The shell may need a restart* if files changed that need one, and when the update renames the plugin (Face ID's 3.0) *Renames Face ID: asks a password later.* **Review full diff in terminal** shows the whole diff. An update fetches the pin, refuses anything but moving forward to it, checks it out and validates it.

## Remove...

For OLED Corners, which has no panel of its own, the card asks and the notch runs `omarchy plugin remove`; the tip says it deletes its folder and that you can install it again here. For Face ID and Profiles the button hands off to their panels instead (Face ID: Settings, then *Remove Face ID from this machine*; Profiles: Manage, then *Uninstall Profiles from this machine*).

## Dismiss

A job that failed shows why, in the row's state, until you press **Dismiss**. The reasons are all on [Troubleshooting](Troubleshooting.md#plugins-and-their-messages).

## The notice

When a job finishes, the rebuilt notch pops down a notice: *Face ID installed* (with **Open setup**, **Enable** or **Restart shell** when there is something to do, otherwise it clears after 5 seconds), or *Couldn't install Face ID* with the reason until you press **Dismiss**. While it runs the notice reads *Installing Face ID...* with a step line: downloading, adding to your plugins, checking what arrived, turning it on.

A job runs as `bin/notch-plugins run` in its own `systemd-run --user` unit, because changing a plugin reloads every plugin and destroys the notch, usually more than once (the folder move, upstream's own rescan, the enable), and every rebuilt notch reads the same status. It decides the outcome from the disk rather than an exit code, and writes its progress to `$XDG_RUNTIME_DIR/kalinewb.notch/plugins-job.json`. A stopped job (TERM or INT) stops upstream's whole process group, removes its staging folder and says so at once. One job runs at a time, never alongside the notch's own update, and never while the session is locked.

## The notch itself

The notch is listed too, with its own update. **Check now** looks for a new version; **Update** appears when there is one.

When GitHub has a newer notch, the resting notch pops down into a small notice with **Later** and **Update**. Update installs it in the background and restarts the shell, and the notch then says *Notch updated* for a few seconds. Later hides that version until a newer one comes out. If an update fails, the notice shows why until you dismiss it. Opening the notch covers the notice, and hovering it never opens the notch, so the pointer can reach the buttons.

The notch checks 20 seconds after it starts and every 6 hours after that. A check fetches origin's HEAD into `.git` and nothing else, so it never reloads plugins. The row says where things stand: *Up to date*, *a version, or a number of changes, available*, *Ahead of GitHub (a development install)*, *Differs from GitHub: update by hand*, *Local edits: update by hand*, *Not a git install*, *Couldn't reach GitHub*, or *This notch doesn't update itself* when *Check for updates* is off in [Settings](Settings.md#check-for-updates).

The update runs as `bin/notch-update run` in its own `systemd-run --user` unit, because the update reloads every plugin and destroys the notch that started it. It runs `omarchy plugin update kalinewb.notch --yes`, decides success from where the checkout ends up (not from the exit code), and writes its progress to `$XDG_RUNTIME_DIR/kalinewb.notch/update.json`. Over IPC: `omarchy-shell notch update check|now|later|dismiss|status`.

## Removing the notch

```sh
omarchy plugin remove kalinewb.notch
```

brings back `omarchy.bar`. The companions are separate plugins in their own folders: turning their settings off gives Omarchy's own menu, OSD and toast back, and `omarchy plugin remove kalinewb.notch-menu` (`-osd`, `-notifications`) removes one for good. Anything installed from the Plugins page is its own plugin and stays.

## Without the notch

Each plugin installs from its own README with `omarchy plugin add <url>`. That installs the repository's current HEAD, not the commit the marketplace verified.

## Over IPC

`omarchy-shell notch plugins open|open:<id>|close|status|refresh`. No IPC call installs, updates, enables, sets up or removes anything; that takes a click in the page, and a confirmed card for install and update.

## Developing

Installing a development checkout, the test hooks that sandbox the plugins folder and the suites that test this page are in the [README](../README.md#developing).
