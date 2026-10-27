# drkhrse Miyoo Bezels
My 4:3 bezels for RetroArch, originally created for [Onion OS](https://github.com/OnionUI/Onion) on the Miyoo Mini+ (but they should also work fine for any 640 x 480 device). This set covers the Game Boy (DMG, Pocket, and Color), Game Boy Advance, Game Gear, Neo Geo Pocket, and more. My intention was to create overlays that are darker than most of the defaults and also have more full screen options with the default aspect ratio. Also added bezels based upon offset video filters that were added by [Jeltr0n](https://github.com/OnionUI/Onion/discussions/708).

![Screenshot](/screenshots/Overview.png)

## Installation
For an Onion OS formatted SD card, copy the entire **drkhrse_miyoo_bezels** folder to RetroArch\.retroarch\overlay\bezels\

All Overlays are designed for default aspect ratio (Settings > Video > Scaling > Keep Aspect Ratio set to On).

Open game and then go to the [Quick Menu](https://github.com/OnionUI/Onion/wiki/Global-Shortcuts) for Retroarch (Menu + Select buttons) > On-Screen Overlay > Overlay Preset > drkhrse_miyoo_bezels > Choose cfg file

Save your configuration afterwards in Quick Menu > Overrides at the Core, Content Directory or per Game level. More info on the setting on the [Onion OS Wiki - How do I save RetroArch settings](https://github.com/OnionUI/Onion/wiki/Frequently-Asked-Questions-%28FAQ%29#how-do-i-save-retroarch-settings) or [here](https://docs.libretro.com/guides/overrides/).

## Integer Scale Overlays

Integer scale overlays have an additional configuration step. These configuration files have "int" in the name.

Go to the Main Menu (use B button from the Quick Menu) > Settings > Video > Scaling > Integer Scale set to On and use the appropiate overlay configuration file.

## Game Boy Pocket / Light - Offset Overlays

Use the following settings ([per Jeltr0n's Overlays](https://github.com/OnionUI/Onion/discussions/708))

- Quick Menu > Core Options
  - GB Colorization= internal
  - Current category for palettes = Essentials
- Color Categories
  - Essentials = (GB-DMG for the original green gameboy palette or GB-Pocket for the pocket grayscale palette)

- Settings
  - Video
    - Scaling
      - Integer Scale= ON
      - Keep Aspect Ratio= ON
      - Video Filter= /GB-GBC/Filters for overlays/(DMG_GreenGrid for green color scheme, GBP_GrayGrid for gray pocket style) (there does not seem to be one built for Game Boy Light colors yet)
  - On-Screen Display
    - On-Screen Overlay
      - Display overlay= ON
      - Overlay Preset= /bezels/drkhrse_miyoo_bezels/GBOffset (filter required)/GBP.cfg (-Noise is an optional variant that replicates the reflective backing of the gb screen) or GBL.cfg
      - Overlay Opacity= 1.00

## Game Boy Color - Offset Overlay

- Quick Menu > Core Options
  - Color Correction = GBC Only (set to OFF if you prefer ultra-saturated unrealistic colors)
  - Color Correction Mode = Accurate for very desaturated, Fast for mild desaturation

- Settings
  - Video
    - Scaling
      - Integer Scale = ON
      - Keep Aspect Ratio = ON
      - Video Filter = /GB-GBC/filters for overlays/GBC_DarkGridReshade
  - On-Screen Display
    - On-Screen Overlay
      - Display overlay = ON
      - Overlay Preset = /bezels/drkhrse_miyoo_bezels/GBOffset (filter required)/GBC.cfg
      - Overlay Opacity = 1.00

## Game Boy Advance - Offset Overlay

- Quick Menu > Core Options
  - Color Correction= ON for realistic color, OFF for saturated color

- Settings
  - Video
    - Scaling
      - Integer Scale = OFF
      - Keep Aspect Ratio = ON
      - Video Filter = /GBA/filters for overlays/GBAOffset
  - On-Screen Display
    - On-Screen Overlay
      - Display overlay = ON
      - Overlay Preset = /bezels/drkhrse_miyoo_bezels/GBOffset (filter required)/GBA__(Choose if you want grid or scanline)_(The number represents how opaque the effect will be)
      - Overlay Opacity = 1.00

## Neo Geo Pocket Color
- Settings
  - Video
    - Scaling
      - Integer Scale = OFF
      - Keep Aspect Ratio = ON
  - On-Screen Display
    - On-Screen Overlay
      - Display overlay = ON
      - Overlay Preset = /bezels/drkhrse_miyoo_bezels/NGP or NGPC
      - Overlay Opacity = 1.00

## Acknowledgements
Big thanks to the [Onion OS](https://github.com/OnionUI/Onion) devs and everyone who contribute to the community at the Retro Game Handhelds discord. **Enjoy!*
