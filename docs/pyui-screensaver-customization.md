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
- `Background image`: choose image/GIF with preview.
- `Background color`: RGB picker with live preview.
- `Overlay opacity`: dim background.
- `Edit layout`: visual widget editor.

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
