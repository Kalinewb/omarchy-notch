# Integrations

Any Omarchy plugin can draw its own panel inside the notch, and so can many widgets that know nothing about the notch.

## Panels

The **Panels** row in [Settings](Settings.md#panels), under Advanced, lists both kinds: plugins that declare an integration, and widgets in your bar whose panel the notch can draw. Each has a switch, and when something isn't shown the reason is there in words, after its name. The state reads *n of m*. The row is absent until at least one plugin or widget can be drawn inside the notch. Switching one off gives that plugin its own window back at once, with no reload. Nothing is hosted until you ask for it: a widget's panel is only drawn in the notch once you switch it on here (`hostedPanels`), and an integration a plugin declares is on until you switch it off (`disabledIntegrations`).

## Why something isn't shown

The words, in the order the notch checks them:

- **Its notch declaration has a problem**: the manifest's `surface` entry is missing or invalid (the detail follows).
- **Needs a newer notch**: it was written for a newer contract than this notch accepts.
- **Written for an older notch**: the contract is older than the oldest this notch accepts. This notch accepts contract 1 only.
- **Plugin isn't enabled**: enable it with `omarchy plugin enable <id>`.
- **Off**: you switched it off in Panels.
- **Loading...**: its integration file is still loading.
- **Couldn't load its notch view**: the integration file failed to load.
- **Not available right now**: the plugin itself says it can't show anything at the moment.

When everything passes the state reads *Shown inside the notch*. `omarchy-shell notch integrations` prints every candidate and why.

## A plugin that declares one

It adds one line to its manifest (`"surface": { "contract": 1 }`) plus an `entryPoints.surface` QML file, and the notch does the rest: the panel opens on the notch's black surface, in its text colours, at its radius, on its motion, and the plugin's own popup stays shut for as long as the notch is showing it.

The written contract is [SURFACE-HOSTING.md](../SURFACE-HOSTING.md): what to declare, the `surfaceHost` object a plugin is handed, how panels are sized and closed, how to claim a line in the resting notch, and the rule for switching your own UI off safely (a surface that exists to warn the user never stands down on an answer that came from outside the shell). `dev/fixtures/platform/plugins/acme.demo` is a complete worked example, and it is what `dev/platform.sh` tests.

## A widget that does not know about the notch

Most Omarchy bar widgets keep their pop-out panel in a `KeyboardPanel`, and the notch can draw that panel inside itself without the plugin changing anything: it opens the panel, takes its content, grows to the size the plugin asked its own card for (on the notch's spring, fading on the notch's timings) and gives it back untouched when it closes. The plugin's own window never maps: it is held down at the one binding that maps it, so the plugin's own state is left alone and simply reads open. That matters, because a panel does its work when it opens (Omarchy's Wifi panel starts its only scan there), and a panel that was drawn without being opened showed a list with no networks in it. The keyboard goes to the target the plugin named, so Escape, the arrow keys and type-to-search work where it lands. When the notch gives the panel back the plugin is told it closed, and anything it runs while open stops; when the plugin closes its own panel, the notch's copy goes down with it.

## Colours

A hosted panel asks Omarchy's `Color` and `Style` itself, so a theme's accent, or a plugin's own hard-coded blue, would paint its toggle buttons, selected rows and graphs on the notch's black. So the notch takes the hue out of what a hosted panel draws (`shaders/mono.frag`) and brings it back as lightness: the more colour a thing had, the lighter its grey, because in the notch emphasis is carried by lightness and never by hue. A button filled with its accent reads as filled; anything already grey does not move at all. There is no switch for it, the same way there is none for the notch's own controls not taking the theme's accent. The same panel in its own window keeps every colour it always had. A theme that pins fills in its style section is reported by [Setup](Setup-points.md#your-theme-tints-panels-in-the-notch).

## From a terminal

```sh
omarchy-shell notch integrations           # every candidate, and why
omarchy-shell notch panel <id> <route>     # open one plugin's panel
omarchy-shell notch hostPanel <widget>     # draw a bar widget's own panel inside the notch
omarchy-shell notch hosting                # what it is holding right now
omarchy-shell notch activities             # the resting-notch queue
```
