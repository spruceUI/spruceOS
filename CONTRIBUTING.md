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
    mappings when required.

- **Validate on the actual device:** test a clean install and an upgrade, boot
  and shutdown/suspend/resume, controls and hotkeys, display/orientation,
  audio, Wi-Fi, storage, and representative emulators/apps. Confirm existing
  supported devices still behave as before, and document any unsupported
  features or required setup.