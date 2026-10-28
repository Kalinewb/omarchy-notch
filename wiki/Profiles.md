# Profiles

Profiles is a separate plugin that gives one machine several desks, each with its own apps, theme, bar, plugins and workspaces. The notch installs and updates it from the [Plugins](Plugins.md) page and hosts its panel; what Profiles does is documented in its own repository, [Kalinewb/omarchy-profiles](https://github.com/Kalinewb/omarchy-profiles), whose README is the authority. This page covers what the notch does with it.

## Profiles

The Plugins page lists it as **Profiles** (`kalinewb.profiles`) at the commit the marketplace verified (version 1.4.0 in this notch's catalogue). Per that README, switching a profile does not apply a template: it captures the desk you are leaving first, so switching back finds it as you left it, and nothing closes when you switch.

## Installing it

Press **Install...** on the Profiles row, read the card, and confirm. Then **Open setup** (offered when Profiles says its own setup isn't finished) opens its panel, which starts on its own Setup list. Per its README nothing there asks for a password or installs anything outside your home directory. The [Setup](Setup-points.md#face-id-isnt-installed) page has a matching row for Profiles with the same buttons.

## What the notch tells Profiles

A profile switch rewrites which plugins are on and what the bar is, so the notch ships a static file, `suite.json`, at the root of its folder, saying what must survive any switch: the notch itself as the bar, its companions, the plugins in its catalogue and the names they had. It is data and nothing in it runs. Profiles shows those plugins as shared, with a locked switch. The contract for the file is in [SURFACE-HOSTING.md](../SURFACE-HOSTING.md#suite-pins).

Profiles' panel is drawn inside the notch like any other hosted panel; see [Integrations](Integrations.md).

## Keybinds that call Profiles

Keys in your `~/.config/hypr/bindings.lua` that call Profiles' script by path stop working if Profiles is removed or reinstalled elsewhere. [Setup](Setup-points.md#profiles-keybinds-point-at-a-missing-script) warns, and does not fix lines you wrote.

## Removing it

The **Remove...** button on the Profiles row hands off to Profiles' own panel (Manage, then *Uninstall Profiles from this machine*, per the notch's catalogue). The notch does not remove it itself.
