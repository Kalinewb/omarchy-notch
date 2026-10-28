# Export and import

Sharing your notch's settings as a short code or a file, and trying someone else's. **This is planned and is not in the notch yet.** Nothing on this page works today; it records what is intended, so the screens and this page can be checked against each other when it lands.

Today the rows are in the panel's source but hidden ([Settings](Settings.md#share-settings)): *Share settings* (**Copy code**, **Save file**) and *Use someone's settings* (**Import**) appear only in a notch that can export. Until then your settings are the `bar.notch` block in `~/.config/omarchy/shell.json`, which you can copy by hand, and **Reset to defaults** is the only way back.

## Planned: what a code holds

The settings the panel and the [rowless keys](Settings.md#settings-with-no-row) cover, the order of your widgets, and the ids of the plugins they name. No passwords, no paths.

## Planned: what import does

Import shows a preview first: one line per changed row, in the panel's own words (such as `Corners  8 px → 12 px`), then asks. Applying it replaces those settings only. It never touches the keys it withholds, `bar.id`, or your plugins (unlike *Reset to defaults*). A snapshot is taken first through [Setup](Setup-points.md#snapshots), so **Undo** puts the previous settings and widget order back.

## Planned: limits and messages

A code is limited to 12,000 characters, a file to 64 KB. The states shown beside the buttons: *Copied*, *Saved*, *Too long* and *Failed* after export; *Nothing copied*, *Not a notch code*, *Damaged*, *Newer notch* and *Too long* when a code can't be read; *Importing*, *Imported*, *Undone* and *Failed* around applying it.

## Planned: from a terminal

A `notch-config` command with export and import verbs, so a code or file can be made and applied without the panel. Its exact verbs will be written here when it exists.

Until it lands, treat everything above as a design, not a feature. If something here disagrees with what the notch does, the notch is right.
