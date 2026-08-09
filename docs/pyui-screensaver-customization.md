# PyUI Screensaver Customization

## Install Backgrounds

Copy user screensaver images to:

```text
/mnt/SDCARD/App/PyUI/screensavers/
```

SMB path:

```text
\\<device-ip>\sdcard\App\PyUI\screensavers
```

Supported formats: `.png`, `.jpg`, `.jpeg`, `.bmp`, `.gif`.

Theme-specific defaults can also be added as:

```text
/mnt/SDCARD/Themes/<ThemeName>/screensaver.png
/mnt/SDCARD/Themes/<ThemeName>/screensaver.gif
```

## Settings

Open `Settings > Screensaver`.

- `Timeout`: global idle timeout before screensaver starts.
- `Background image`: choose `Random boxart`, an image, or a GIF, with preview.
- `Background color`: RGB picker with live preview.
- `Overlay opacity`: dim background.
- `Edit layout`: visual widget editor.

## Random Boxart

Pick `Random boxart` as the `Background image` to cycle through the box art already on the
card instead of a fixed background. Covers are drawn centred at their correct aspect ratio,
with the `Background color` filling the space either side.

The pool is every image under:

```text
<Roms>/<System>/Imgs/
```

on both SD cards, including mirrored subfolders. Order is random.

Each cover is shown for 15 seconds. To change that, set `boxartIntervalSec` in the
`screensaver` block of the active theme's `config.json`:

```json
"screensaver": {
    "bgImage": "__boxart__",
    "boxartIntervalSec": 30
}
```

Notes:

- The card is scanned once, in the background, the first time the boxart screensaver runs.
  Box art added afterwards is picked up the next time PyUI restarts.
- Clock, date and battery widgets still draw on top of the cover. The shipped layout puts
  them in the middle of the screen, so you will probably want to move them out to the edges
  with `Edit layout`.

## Visual Layout Editor

- D-pad: move selected widget.
- `L1` / `R1`: decrease/increase widget size.
- `L2` / `R2`: cycle quick colors.
- `START`: open RGB picker for selected widget color.
- `Y`: change font for clock/date/text, or battery style for battery.
- `X`: show/hide selected widget.
- `SELECT`: switch selected widget.
- `A`: save.
- `B`: cancel.

Included widget fonts:

- `PressStart2P-Regular.ttf`
- `VT323-Regular.ttf`
- `Silkscreen-Regular.ttf`
- `PixelifySans.ttf`
- `Orbitron.ttf`
- `Audiowide-Regular.ttf`
- `BungeeShade-Regular.ttf`
- `EmilysCandy-Regular.ttf`

Battery styles:

- `percent`
- `blocks`
- `bar`
- `pill`
- `segments`

## Performance Notes

Animated GIFs are only loaded after the screensaver timeout and are freed when the user wakes the device. Large 1280x720 GIFs with many frames can still use more memory while active, so prefer short optimized loops.
