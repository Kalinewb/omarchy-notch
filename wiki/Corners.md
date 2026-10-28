# Corners

OLED Corners is a separate plugin that paints black rounded corners in the four physical corners of every monitor, handy on OLED panels and on laptops whose display glass is rounded. The notch installs and updates it from the [Plugins](Plugins.md) page; what the plugin does and how to configure it is documented in its own repository, [Kalinewb/omarchy-oled-corners](https://github.com/Kalinewb/omarchy-oled-corners), whose README is the authority.

Not to be confused with the notch's own **Corners** row in [Settings](Settings.md#corners), which rounds the notch, not the screen.

## OLED Corners

The Plugins page lists it as **OLED Corners** (`kalinewb.oled-corners`) at the commit the marketplace verified (version 1.1.0 in this notch's catalogue). It needs no setup of its own: the corners appear the moment it is enabled. Per its README, with no config file the radius follows Hyprland's `decoration:rounding`, and `~/.config/omarchy/oled-corners.json` can override the radius, colour and per-monitor radius.

## Its settings panel

Per that README, when the notch is your bar, OLED Corners offers a settings panel that opens inside the notch, listing *All monitors* and one row per screen. Open it with `omarchy-shell oled-corners settings`. Its keys: Left and Right change the radius, F or Backspace hands the row back to the level above ("Follow"), Up and Down pick a row, Escape closes. It is a hosted panel like any other: see [Integrations](Integrations.md) for switching it off.

## Corners pop in on screen change

Hyprland animates a layer as it maps, and OLED Corners' layers map again on every monitor change, so without a rule they fade in instead of just being there. [Setup](Setup-points.md#corners-pop-in-on-screen-change) notices this when OLED Corners is installed and offers a Fix: a marked block in `~/.config/hypr/looknfeel.lua` with Omarchy's own `no_anim=true` layer rule for `omarchy-oled-corners`. Nothing in the block mentions the notch, so it keeps working without it.

## Removing it

OLED Corners has no uninstall in its own panel, so the **Remove...** button on its row asks in the notch and runs `omarchy plugin remove kalinewb.oled-corners` for you. Per its README, two small files can outlive it if you made them: `~/.config/omarchy/oled-corners.json` and `~/.local/state/kalinewb.oled-corners/`.
