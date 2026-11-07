# Where things live

Paths are relative to the root of the card.

| What | Where |
|------|-------|
| Boot entry points | `.tmp_update/`, `miyoo/`, `miyoo355/`, `trimui/` |
| Runtime and helper scripts | `spruce/scripts/` (`helperFunctions.sh` is the shared library) |
| Per-device code and config | `spruce/scripts/platform/<family>/<PLATFORM>.sh` and `.cfg` |
| Emulator launch scripts | `spruce/scripts/emu/` (per-emulator code in `lib/`) |
| Network services | `spruce/scripts/network/` |
| Settings change commands | `spruce/scripts/applySetting/` |
| Task scripts | `spruce/scripts/tasks/` |
| Binaries, 32-bit | `spruce/bin/` |
| Binaries, 64-bit | `spruce/bin64/` |
| Device-specific binaries and libraries | `spruce/<device>/` (`a30`, `flip`, `h700`, ...) |
| Flags | `spruce/flags/` |
| Archives unpacked on the device | `spruce/archives/` |
| Apps | `App/<name>/` |
| Frontend | `App/PyUI/` (code in `main-ui/`) |
| Upgrade scripts | `App/spruceRestore/UpgradeScripts/<version>.sh` |
| Emulators and their config | `Emu/<SYSTEM>/` |
| RetroArch | `RetroArch/` (default configs in `platform/*.cfg.bak`) |
| Default settings | `Saves/spruce/spruce-config.json` |
| User data: saves, states, screenshots | `Saves/` |
| Live RetroArch configs | `Saves/ra-configs/` |
| Backups of settings | `Saves/spruce/backups/` |
| Logs | `Saves/spruce/` |
| Games and box art | `Roms/<SYSTEM>/` and `Roms/<SYSTEM>/Imgs/` |
| Themes | `Themes/` |

Anything that must survive an update belongs in `Saves/`. Only settings merges and upgrade scripts change it.

# Design primitives

Generally the spruceOS team plays it "fast and loose" about incorporating new
features; however, certain design elements should be kept in mind, in order to
maximize the chances of getting your contributions merged.

- **Human-first design:** New features should serve our users, our devs, or
  both. Libraries and binaries may be kept on older versions if the newer ones
  would degrade the user experience, e.g. we tried newer Python versions than
  what we presently use, but did not implement them due to slower loading.

- **Expressed opinions should favor minimalism:** Overlays and shaders should
  always be opt-in. Visuals in general are very subject to individual variations
  in taste; we should strive to ship defaults that are the least offensive to
  the greatest proportion of users. This usually equates to "less".

- **Distracting features should be opt-in:** LEDs should be off by default. On-
  screen displays should be off by default when they convey information that
  can already be understood without them, e.g. no OSD for backlight level, as
  the panel already conveys this information. 

- **The spruce card should remain portable:** One of the definining features of
  spruceOS is that the same SD card can be loaded into any of dozens of devices
  and "just work". Features that are tightly coupled to a particular piece of
  hardware need to be appropriately contained. Code shared between multiple
  devices needs to be handled with care.


# Traps

- **Do not add defaults for optional functions in `device.sh`:** some callers
  use `command -v` to check whether a function exists, so a default changes
  what they do. Before adding one, search for the function's name.

- **Upgrade scripts run again on every full update:** the updater deletes
  `.lastUpdate`, so every script in `UpgradeScripts/` re-runs. They must be safe
  to repeat, and anything they set overrides a change the user made since.

- **`default_configs` only reach new installs:** those files are only copied
  when missing. Existing users need an upgrade script to get a change.

- **Keep a file's line endings:** some files are CRLF. Check the diff size before
  committing: a small change showing hundreds of lines means they were rewritten.

- **Do not log success without checking for it:** a log line that always says a
  step worked hides the failure when it does not.


# Branches, versions and releases

- **`Development`:** the working branch. Nightlies are built from here.

- **`main`:** a snapshot of the current stable release. Stable releases are built
  from here.

- **Versions:** even is stable and odd is nightly, e.g. 4.5.6 and 4.5.7. The
  current version is in `spruce/spruce`.

- **Pull requests:** changes to `App/PyUI/main-ui` and `.github/` need review from
  their code owners (see `.github/CODEOWNERS`).

- **Packages:** tracked files ship on the card unless excluded in the workflows
  under `.github/workflows/`. If a file should not reach users, exclude it there.


# Onboarding a new device

Before a new device is considered supported, make sure its identity and behavior
are wired through every relevant layer. Reuse an existing platform or device
implementation when the hardware and behavior match; add device-specific code
only where needed.

- **Identify and detect the device:** establish its hardware/OS identifiers and
  assign a stable `PLATFORM` name and `PLATFORM_FAMILY`. Update detection in
  `spruce/scripts/helperFunctions.sh` and any other entry points that must
  recognize the device. Keep `device_names()` and PyUI's `-device` identity in
  sync.

- **Add platform defaults and behavior:** provide the appropriate platform
  `.cfg` and `.sh` files under `spruce/scripts/platform/`, or explicitly reuse
  a shared family implementation. Cover hardware-specific input, display,
  power, audio, storage, Wi-Fi, LEDs, and other features as applicable. Avoid
  assumptions that are only valid for a related model.

- **Integrate PyUI:** map the device identifier in
  `App/PyUI/main-ui/devices/device_factory.py` to an existing compatible device
  class or implement the required device behavior. Check screen dimensions,
  controls, key mappings, brightness, and device-specific settings.

- **Add emulator and system defaults:**

  - RetroArch defaults: `RetroArch/platform/retroarch-<PLATFORM>.cfg.bak`.

  - PPSSPP defaults: `Emu/PSP/default_configs/SYSTEM/ppsspp-<PLATFORM>.ini`
    and `Emu/PSP/default_configs/SYSTEM/controls-<PLATFORM>.ini`.

  - DraStic defaults and reset copies:
    `Emu/NDS/config/drastic-<PLATFORM>.cfg`,
    `Emu/NDS/config/drastic-<PLATFORM>.cfg.bak`,
    `Emu/NDS/resources/settings_<PLATFORM>.json`, and
    `Emu/NDS/resources/settings_<PLATFORM>.json.bak`. The `settings_...json`
    pair is optional; add it only when the device needs separate Steward
    settings.

  - Mupen64Plus controller mapping:
    `Emu/N64/mupen64plus/pad/InputAutoCfg-<MUPEN_PAD_TABLE>.ini`.
    `<MUPEN_PAD_TABLE>` is set by the platform `.cfg`; use the platform name
    when no shared/table alias is configured.

  - Flycast controller mapping:
    `Emu/DC/default_configs/flycast/pads/<FLYCAST_PAD_MAP>/SDL_<controller>.cfg`.
    `<FLYCAST_PAD_MAP>` is set by the platform `.cfg`; include the SDL mapping
    file(s) used by that map.

  - YabaSanshiro controller mapping:
    `Emu/SATURN/pad/keymap-<SATURN_PAD_TABLE>.json`, or
    `Emu/SATURN/xx-pad/keymap-<PLATFORM>.json` for the Anbernic XX pad maps.

  - ScummVM defaults:
    `Emu/SCUMMVM/.config/scummvm-<SCUMMVM_TARGET>/scummvm.ini`.

  - RetroArch controller autoconfiguration, only if the device needs its own
    SDL, udev, or linuxraw mapping:
    `RetroArch/.retroarch/autoconfig/<driver>/<controller>.cfg`.

  - DSperate generally shares configs by control layout. Dedicated configs in
    `Emu/NDS/dsperate-configs/` are used where a device or mode needs different
    settings: A30 has its own rendering and performance settings; V10 and RGB30
    need different hotkeys because they lack a menu/guide button; Zero40 needs
    touchscreen settings; Pixel2 needs settings for its inverted buttons; and
    Tate mode uses a rotated-screen config. For a new device, add a dedicated
    config only if its controls, display, touch, or hotkeys cannot use an
    existing one, and wire it into `spruce/scripts/emu/lib/dsperate_functions.sh`.

  - Update the relevant existing `Emu/<SYSTEM>/config.json` device lists or
    mappings when required; Check for `PLATFORM` checks in the scripts found in `spruce\scripts\emu\lib` and add new cases where needed. 

- **Validate on the actual device:** test a clean install and an upgrade, boot
  and shutdown/suspend/resume, controls and hotkeys, display/orientation,
  audio, Wi-Fi, storage, and representative emulators/apps. Confirm existing
  supported devices still behave as before, and document any unsupported
  features or required setup.