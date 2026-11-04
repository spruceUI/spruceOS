# Theming the in-game menu

The in-game menu (the one RetroArch shows when you tap the menu button mid-game)
reads its look from an `igm.json`. This folder holds the colourways that ship
with spruce; a theme can also carry its own.

Start by copying `spruce.json` — it lists every key with its default value.

## Where the file comes from

The binary looks in three places and uses the first one it finds:

1. `Themes/<your theme>/igm.json` — shipped with a theme
2. `RetroArch/igm.json` — written by **Settings → In-Game Menu Settings →
   Colors**
3. `RetroArch/igm/spruce.json` — the shipped default

**A theme's file wins outright.** If your theme ships an `igm.json`, the user's
colourway setting stops having any visible effect and nothing on screen explains
why. Only ship one if matching your theme is the point.

The file is read **once, when a game launches**. Changing it mid-game does
nothing; quit to the menu and start a game again.

## Writing one

Every key is optional. Anything you leave out keeps its default, so a colourway
only needs the colours:

```jsonc
{
  "name": "purple",
  "colors": {
    "selection": "#B47FE52E",
    "accent":    "#B47FE5D9",
    "text":      "#E5DCEDFF"
  }
}
```

- Colours are `#RRGGBB` or `#RRGGBBAA`. Six digits means fully opaque.
- `//` and `/* */` comments are fine. **Trailing commas are not** — one stray
  comma and the whole file is rejected.
- Sizes are percentages of the screen, never pixels, so one file works on every
  device from 640x480 up to 1280x720.

If the file fails to parse, the menu silently falls back to its built-in look. To
see why, turn on **Settings → Emulator Settings → Verbose emulator logging** and
check `Saves/spruce/retroarch.log` for `[IGM theme]` lines — without that setting
the warnings go nowhere.

## Keys

### `colors`

| key | default | what it paints |
|---|---|---|
| `dim_bg` | `#000000D9` | the whole screen, behind the menu |
| `panel_bg` | `#00000000` | behind the menu rows. Transparent by default — set it to draw a solid card |
| `selection` | `#C9A2272E` | the highlighted row |
| `accent` | `#C9A227D9` | the bar down the left of the highlighted row |
| `title_line` | `#665C5466` | the rule under the title |
| `text` | `#BDAD91FF` | unselected rows |
| `text_selected` | `#D5C4A1FF` | the highlighted row's label |
| `text_title` | `#689D6AFF` | the title |
| `text_shadow` | `#000000C0` | the drop shadow behind all text |
| `battery` | `#BDAD91FF` | the battery percentage |

### `layout`

| key | default | notes |
|---|---|---|
| `margin_pct` | `2.0` | of screen width |
| `panel_w_pct` | `38.0` | of screen width |
| `item_h_pct` | `8.0` | of screen height, per row |
| `title_h_pct` | `8.0` | of screen height |
| `panel_x_pct` | `null` | `null` means "one margin from the left" |
| `panel_y_pct` | `null` | `null` means "vertically centred" |
| `separator_inset_pct` | `10.0` | of panel width, each end of the title rule |
| `separator_h_px` | `1` | `0` hides the rule |
| `arrow_inset_pct` | `10.0` | of panel width, for the Save/Load arrows |
| `accent_w_pct` | `1.25` | of panel width, minimum 2px |
| `accent_bar` | `true` | |
| `text_baseline` | `0.68` | where text sits in a row, as a fraction of its height |
| `title_baseline` | `0.68` | |
| `shadow` | `true` | |
| `shadow_offset_px` | `2` | |
| `scale` | `1.0` | multiplies every size above |
| `battery` | `true` | show the battery percentage |
| `preview` | `true` | show the save state screenshot |

### `font`

| key | default | notes |
|---|---|---|
| `path` | the stock `nunwen.ttf` | **relative to this file**, so a theme can just say `"myfont.ttf"` and mean its own |
| `size_pct` | `5.0` | of screen height, for the menu rows |
| `size_small_pct` | `3.5714286` | of screen height, for the title |
| `battery_size_pct` | `3.5714286` | drives where the battery percentage sits |

A font path that does not exist falls back to the stock font and logs it. It will
not look broken, so check the log if your font seems to be ignored.

### `text` and `labels`

| key | default |
|---|---|
| `text.title` | `"spruceOS Menu"` |
| `text.auto` | `"Auto"` |
| `text.slot` | `"Slot"` |
| `text.max` | `"Max"` |
| `text.on` / `text.off` | `"On"` / `"Off"` |
| `text.arrow_left` / `text.arrow_right` | `"<"` / `">"` |
| `labels.resume` | `"Resume"` |
| `labels.save` | `"Save"` |
| `labels.load` | `"Load"` |
| `labels.ff_speed` | `"FF Speed"` |
| `labels.reset` | `"Reset"` |
| `labels.retroarch` | `"RetroArch Menu"` |
| `labels.exit` | `"Exit Game"` |
| `labels.disc` | `"Disc"` |
| `labels.screenshot` | `"Screenshot"` |
| `labels.undo_save` | `"Undo Save"` |
| `labels.undo_load` | `"Undo Load"` |
| `labels.show_fps` | `"Show FPS"` |
| `labels.mute` | `"Mute"` |
| `labels.rewind` | `"Rewind"` |
| `labels.shader` | `"Shader"` |

The Save and Load rows read `"<labels.save> <text.slot> 3"`, or
`"<labels.save> <text.auto>"` on the auto slot. You supply the words; the menu
assembles them. The FF Speed row reads `"<labels.ff_speed> 3x"`, or
`"<labels.ff_speed> <text.max>"` when uncapped. The Disc row reads
`"<labels.disc> 2/3"`, and the toggles read `"<labels.show_fps>: <text.on>"`.

A theme only sets the words. Which rows appear is the player's choice, not the
theme's — see below.

## Which entries appear

`RetroArch/igm_items.json` lists the entries in display order:

```json
{ "items": ["resume", "save", "load", "reset", "retroarch", "exit"] }
```

**Settings → In-Game Menu Settings** writes this file, and a game launch creates
it from those toggles if it is missing. Editing it by hand works too, and the
toggles keep a hand-made order. Backup and restore carry it. Unknown ids are
skipped and a repeated id appears once; an empty or broken file gets the
binary's built-in list. Resume, when listed, is always first and Exit always
last. B always resumes, whatever the list.

Ids: `resume`, `save`, `load`, `ff_speed`, `reset`, `retroarch`, `exit`, `disc`,
`screenshot`, `undo_save`, `undo_load`, `show_fps`, `mute`, `rewind`, `shader`.

`disc` only appears in games with more than one disc. `shader` never appears on
the Miyoo Mini. FF speed, Show FPS, Rewind and Shader changes are saved to the
RetroArch config; Mute lasts until the game closes.

Setting `text.title` to `""` hides the title but keeps its row height — set
`title_h_pct` to `0` to reclaim the space.

## Two things that will catch you out

**Nothing is range-checked.** Values are applied exactly as written, on purpose.
The menu shows as many rows as fit on screen and scrolls the rest, with a
scrollbar on the panel's right edge. Bigger rows therefore mean more scrolling
rather than rows off the screen.

The device scale is `1.0` everywhere except **Pixel2 and RGDS, where it is 1.2**,
so the same `item_h_pct` fits fewer rows on those two. At the default of `8.0`
all six default entries fit everywhere.

Explicit `panel_x_pct` / `panel_y_pct` are *not* multiplied by the device scale,
while the sizes are — "put it at 40% of the screen" should mean that everywhere.
The consequence is that `panel_x_pct: 2.0` will not line up with the automatic
margin on Pixel2 and RGDS. Use `null` if you want the automatic placement.

**The Miyoo Mini ignores some keys.** It has no GPU, draws with a fixed bitmap
font and has no shadow pass at all. It silently ignores:

`font.path`, `font.size_pct`, `font.size_small_pct`, `font.battery_size_pct`,
`colors.text_shadow`, `layout.shadow`, `layout.shadow_offset_px`,
`layout.text_baseline`, `layout.title_baseline`

`layout.scale` does apply there, but the text can only grow in whole steps — 1.5
takes it from 2x to 3x, while 1.2 leaves the text alone and grows only the panel.

## Testing

Copy a file onto the card and launch any game:

```sh
cp /mnt/SDCARD/RetroArch/igm/purple.json /mnt/SDCARD/RetroArch/igm.json
```

To test a theme's copy, put it at `Themes/<your theme>/igm.json` and make sure
that theme is the active one. Delete it to fall back to the colourway.
