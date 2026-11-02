# Troubleshooting

Things that look like faults and are not, or that the notch cannot change. None of them is on the
*Needs attention* page, because there is nothing to press.

## Plugin panels use my theme's colours

When a plugin's panel opens inside the notch, its hover highlights, selection and outlines can come
out in your theme's colour instead of white. The notch's own switches and buttons are unaffected.

A plugin's panel asks Omarchy's Style helpers for its fills, and some themes pin those fills
(`selected-color`, `hover-cursor-color` and so on, in the theme's `shell.toml` `[style]` section) to a
colour of their own. A pinned token makes the helper ignore the white the notch hands it. Those
helpers are shared with the whole desktop, so the notch cannot change them just for itself.

If it bothers you, set the tokens to `"foreground"` in the theme's `shell.toml`, or pick a theme that
leaves them at the default. That changes them everywhere, not only in the notch. Text is unaffected
either way.

## Every point the notch checks

`notch-setup detect --all` in a terminal lists every point and every state, including the ones the
page never shows: whether the bar is hidden, whether the notch is the active bar, whether Omarchy's
own files moved, whether a test notch is still running. The page lists only what a person can act on.
