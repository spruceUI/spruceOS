# ScummVM

By default, 64-bit devices use the standalone ScummVM emulator. The RetroArch core was removed to reduce download size (~105MB).

## Restoring the RetroArch core

1. Download `scummvm_libretro.so` for aarch64 from https://buildbot.libretro.com/nightly/linux/aarch64/latest/
2. Place it in `RetroArch/.retroarch/cores64/`
3. In `Emu/SCUMMVM/config.json`, find the `Emulator_64` section and add `"scummvm_libretro"` to the `options` array:
   ```json
   "options": [
     "scummvm_libretro",
     "scummvm-standalone"
   ]
   ```
4. You can now select between standalone and RetroArch core in the emulator picker.
