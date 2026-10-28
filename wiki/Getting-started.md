# Getting started

The notch is a bar for Omarchy that is a black rectangle hanging from the top centre of the screen: it rests pitch black, and opens to show every widget from your bar layout, plus the time and what is playing.

It replaces `omarchy.bar` as a full `bar` plugin, and hosts the same widgets and panels.

## Install

From the Omarchy plugin marketplace, or in a terminal:

```sh
omarchy plugin add https://github.com/Kalinewb/omarchy-notch --yes
omarchy plugin enable kalinewb.notch
```

That installs a git checkout, so the notch can update itself ([Plugins](Plugins.md#the-notch-itself)), and `omarchy plugin update kalinewb.notch` works too.

The notch is one plugin. Its three companions (the menu, the OSD and the notification toast) come from its own `companion/` folder, and it installs each one only when you switch on the setting that needs it. Face ID, Profiles and OLED Corners install from its [Plugins](Plugins.md) page, at the commits the Omarchy marketplace verified.

## The first minute

- **Open it.** By default hovering the notch or clicking it opens it (`openWith` is `hover` and `click`), after the pointer has rested 60 ms. What it opens to is the *Opens to* row: the widgets by default. See [Settings](Settings.md#open-with).
- **Open Settings.** Long right-click the notch (hold the right button), or run `omarchy-shell notch settings`. The notch grows down into the panel; click outside, press Escape or press ✕ to close it. See [Settings](Settings.md).
- **Check the machine.** In Settings, the **Setup** button opens a list of things about this machine that stop the notch working the way you want, each with a **Fix** where one is safe. A number beside it counts what needs attention. See [Setup points](Setup-points.md).
- **At rest it is empty.** Nothing shows on the resting notch until you pick something in *At rest*. A new track, a charger going in or a low battery still widens it for a few seconds (see *Peeks* in [Settings](Settings.md#peeks)).
- **Hide it.** `omarchy-toggle-bar` slides it up into the screen edge; with *Auto-hide* on it also hides at rest until the pointer reaches for the top edge.

## Guided setup (coming)

A guided setup, one question at a time, is planned and is not in the notch yet. Until it lands, the nine rows under **Look**, **Open** and **In the notch** in [Settings](Settings.md) are the quick way to a notch that suits you. When a guided setup exists, a **Guided setup** button appears in the Settings header. The button stays hidden in a notch that has none.

## Go back to another bar

```sh
omarchy plugin enable omarchy.bar
```

Or enable your own clone. To remove the notch altogether, see [Plugins](Plugins.md#removing-the-notch).

## Where to read next

- [Settings](Settings.md) for every row.
- [Troubleshooting](Troubleshooting.md) if something is off.
- [Integrations](Integrations.md) for how other plugins' panels end up inside the notch.
