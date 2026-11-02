# Platforms

`helperFunctions.sh` names the platform (`PLATFORM`) and its family (`PLATFORM_FAMILY`), then sources
`<family>/<PLATFORM>.cfg` (its variables) and `<family>/<PLATFORM>.sh` (its functions, over the defaults in
`device.sh`). A platform with no family keeps both files directly in `platform/`.
A family shares one file that each board's file sources: `AnbernicXXCommon.cfg`, `dArkMossCommon.sh`, `a133p.sh`
and so on.

## oakMOSS: base, chip and brand

oakMOSS is a base OS that runs on more than one chip and carries more than one brand, so its boards stack three
layers, each sourcing the one below:

- the board, `oakmoss/<PLATFORM>.{cfg,sh}`: its cfg names its chip, `export PLATFORM_CHIP="a133p"`;
- the brand, `oakmoss/<Brand>Common.sh` (`MagicXCommon.sh`, `PowkiddyCommon.sh`; the single Brick keeps its
  brand's part in `BrickOakMOSS.sh`): what that brand's boards share on any chip, such as the pad;
- the base, `oakmoss/oakMOSSCommon.sh`: what every oakMOSS board shares. It first sources the chip's oakMOSS
  layer, `oakmoss/oakmoss_<chip>.sh` (`oakmoss_a133p.sh`), which holds what depends on the chip and the base image
  built for it and sources the chip file other bases share (`platform/a133p.sh`).

A board on a new chip adds `oakmoss_<chip>.sh` and, where no other base has one yet, `platform/<chip>.sh`. Its
boards report `OAKMOSS_<CHIP>` (`OAKMOSS_A133P`) after their own name in `device_names`, for the Emu and App
config lists, since builds differ by chip.

## Variants

A variant is a platform that is another one with a few differences: the same board on a different base, say.
Its cfg declares the platform it builds on and sources that platform's cfg first:

```sh
export PLATFORM_PARENT="Brick"
. /mnt/SDCARD/spruce/scripts/platform/tina-stock/Brick.cfg
# ...then only what differs
```

Its `<variant>.sh` works the same way. The per-platform data spruce ships under the platform's name (RetroArch,
PPSSPP, DraStic and AdvanceMAME configs, pad tables, `Emulator_<platform>` core picks, the firstboot flag) then
falls back to the parent's until the variant ships its own. Scripts look these up with:

- `platform_path "<path with %s for the platform>"`: the variant's file if it exists, else the parent's, else
  the variant's (for a file the caller creates);
- `platform_names`: the variant's name, then the parent's, for keys that are not files.

A platform without `PLATFORM_PARENT` resolves exactly as it did before: `%s` is its own name. One level only: a
parent is never itself a variant.
