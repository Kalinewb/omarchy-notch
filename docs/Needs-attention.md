# Needs attention

The notch's page for the rare day something stops it working (the IPC view is still `setup`, the
script is `bin/notch-setup`). It is quiet by design: no rows on a healthy machine, one title, one
line and one button per problem, and no ids, file names or commands in the default view.

## What may appear on the page

A point is on the page only if every one of these is true. Otherwise it is a developer check
(`notch-setup detect --all`), an automatic repair (`notch-setup auto`), a hint in Settings, or nothing.

1. It is true now and something the user wanted is not working because of it (not a state, a tip or a future risk).
2. The check cannot be wrong: it reads the thing itself (does the service answer on the bus? is the file there?), not a proxy flag such as the plugin list's `active`. A check that cannot decide shows nothing.
3. The notch cannot repair it silently and safely. If it can, it does, and a snapshot stays under *Earlier fixes*.
4. The user can act in one press, or in one plain sentence.
5. One title and one line in plain words: no ids, paths, commands, `file(s)` or words like companion, upstream, layer.
6. It is not someone else's choice or page (optional plugins not installed, updates, key clashes).
7. A migration or transitional point carries a removal date in its code (`removeby_of` in `bin/notch-setup`).

`dev/attention.sh` holds `bin/notch-setup` to this.

## What is on the page, what is automatic

| Row | Button | When |
|---|---|---|
| The notch menu / Volume pop-ups didn't move to the notch | Try again | the helper is off, or the notch could not install it |
| Some menu keys ignore the menu switch | Move keys | hand-written binds call the notch's menu directly |
| A bar item shows nothing | Restart bar (asks first) | a widget loaded but drew nothing |
| Face ID / Profiles needs one more step | Finish setup | installed and on, its own setup unfinished |
| Face ID's old name is still in your settings | Finish the move | removed after 2027-06-01 |
| Your Profiles keys point to a missing file | Reinstall | keys call a script that is gone |
| OLED Corners flash when a screen changes | Add the rule | removed after 2027-03-01 (see below) |

Automatic, no row, snapshot kept: stale plugin ids in the notch's settings; leftover notch keybinds;
a bar item whose plugin was removed; the notch's own plugin backups older than 30 days; and "Notch
only" when nothing owns `org.freedesktop.Notifications` (the notch switches back to Omarchy's own
pop-ups, without any signal).

Bar switching: leaving the notch for another bar parks the notifications helper
(`notch-companion park`, run as the notch is destroyed, and only if `shell.json` no longer names the
notch as the bar), which gives Omarchy's own service back. Coming back, the notch switches the
helper on again if "Notch only" is set. A restart or an update of the notch leaves it alone.

## OLED Corners: what its own repo should carry

The notch's `Add the rule` row is transitional. The rule belongs to the plugin, installed with
consent. This repo does not edit `Kalinewb/omarchy-oled-corners`; the change to make there:

- On install (and only then), append this block to `~/.config/hypr/looknfeel.lua`, once:

  ```lua
  -- >>> kalinewb.oled-corners: no_anim -- delete this block to undo
  hl.layer_rule({ match = { namespace = "omarchy-oled-corners" }, no_anim = true, animation = "none" })
  -- <<< kalinewb.oled-corners: no_anim
  ```

  then `hyprctl reload`, and verify `hyprctl configerrors` is empty (roll the file back if not).
- Consent line, on the notch's Plugins card for OLED Corners (the card's second line, after
  "Plugins run unsandboxed inside your shell."): **Also adds one animation rule to your Hyprland
  config. Remove takes it out.**
- On Remove, delete exactly that marked block (and nothing else in the file), then `hyprctl reload`.
- The notch's row detects the rule by the `no_anim=true` layer rule for `omarchy-oled-corners`,
  whoever wrote it, so a plugin-written block retires the row by itself. The row and its fix are
  deleted on 2027-03-01 (`removeby_of oled-corners-still`).
