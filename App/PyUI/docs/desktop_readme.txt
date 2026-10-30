PyUI on a desktop
=================

PyUI runs in a window on a Mac or PC as the DESKTOP device, for working on PyUI,
themes and PyUI-based apps without a handheld: any resolution, any theme,
keyboard or gamepad, scripted input and screenshots. It is the real launcher
(mainui.py) reading this SpruceOS checkout as its SD card.

Setup: Python 3.10 or newer and PySDL2 with SDL's libraries.

    python3 -m pip install pysdl2 pysdl2-dll

Running
-------

    python3 App/PyUI/main-ui/desktop.py
    python3 App/PyUI/main-ui/desktop.py --res 1280x720 --scale 2
    python3 App/PyUI/main-ui/desktop.py --themes ~/themes --theme MINIMAL

--res takes any size; spruce devices use 640x480, 720x480, 752x560, 720x720,
960x720, 1024x768, 1280x720 and 480x800. --scale zooms the window (screenshots
stay at --res). --theme is kept for later runs, like a theme picked in Settings.
desktop.py --help lists every option. Arguments it does not know go to
mainui.py, e.g. -msgDisplay "Hello" -msgDisplayTimeMs 3000.

Keys (RetroArch's layout plus Menu): arrows = D-pad, X = A, Z = B, S = X, A = Y,
Q / W = L1 / R1, 1 / 2 = L2 / R2, Enter = Start, Right Shift = Select,
M = Menu, F8 = screenshot, Esc = quit. A USB or Bluetooth gamepad works too,
mapped by position to the Nintendo layout (Guide = Menu).

Folders
-------

  --sdcard  Read only: App/, Emu/, Themes/, Saves/spruce/spruce-config.json.
            Default: the SpruceOS checkout desktop.py is in.
  --roms    Read only. Default: <sdcard>/Roms (a few homebrew games). Box art
            resizing is off, since it writes next to the ROMs.
  --themes  Default: <sdcard>/Themes, which has SPRUCE only; Settings > Theme
            lists every theme in the folder. Kept for later runs, like
            --theme. A theme with no config_<W>x<H>.json for --res is
            converted in its folder, as on a device. Keep downloaded themes
            outside the checkout.
  --data    Everything PyUI writes: Saves/ (configs, state, favorites,
            recents), Collections/, logs/pyui.log, screenshots/<W>x<H>/.
            Default: ~/.pyui-desktop. Delete it for a fresh card.

On the first run Saves/pyui-config.json is made from App/PyUI/py-ui-config.json
and Saves/spruce/spruce-config.json is copied from the SD card. Settings changed
in PyUI are kept in them.

Nothing runs the CFW's scripts or touches hardware: every "...Cmd" entry, the
About entries and the CFW tasks are left out of the configs; display, volume,
Wi-Fi and Bluetooth settings are saved and otherwise ignored; Wi-Fi is off and
the battery shows 87%. Games and apps are not launched (the log says which
would have been), and Power Off ends the run.

PyUI exits by itself when it wants a fresh start - after a theme change, a
theme conversion, a mode change, a deleted ROM, a crash - and spruce's
principal.sh starts it again. desktop.py does the same, so the window closes
and opens again; a --script carries on where it was. The run ends with Esc,
closing the window, Power Off or the end of a --script. If PyUI keeps exiting
as it starts, desktop.py gives up after three tries.

Scripts and screenshots
-----------------------

--script plays button presses before handing over to the keyboard:

    desktop.py --script "right,a,shot:games,select,wait:12,shot:games_grid"

Tokens: up down left right a b x y l1 r1 l2 r2 start select menu;
shot:<name> saves the screen as <out>/<name>.png (default
<data>/screenshots/<W>x<H>/); wait:N lets PyUI run N idle ticks of at least
1/12 s, for things that take time. --quit-after-script exits when the script
ends; --headless (no window, implies it) is for CI and quick checks:

    for res in 640x480 752x560 1280x720; do
        desktop.py --headless --res $res --script "shot:main,right,a,shot:games"
    done

A run exits with status 1 if PyUI leaves the menu before the script ends:
usually the script no longer matches the screens.

From another app
----------------

An app with "pyuiEntry" in its config.json (App/Cheevos) runs inside this
PyUI, as on a handheld (apps/native_app.py). Apps that bring PyUI up
themselves (such as Cheevos's own desktop runner) get the desktop the same
way they get a handheld:

    from devices.device_factory import initialize_device
    initialize_device("DESKTOP", main_ui_mode=False)

The factory imports only the selected device, without loading the launcher.
mainui.initialize_device remains available for existing apps. desktop.py
configures the device through environment variables, which such an app sets
instead:

  PYUI_DESKTOP_RES                 640x480
  PYUI_DESKTOP_SCALE               window zoom, 1
  PYUI_DESKTOP_THEME               theme to switch to
  PYUI_DESKTOP_SDCARD              read-only SD card, this checkout
  PYUI_DESKTOP_ROMS                <sdcard>/Roms
  PYUI_DESKTOP_DATA                ~/.pyui-desktop
  PYUI_DESKTOP_SCRIPT              script, as --script
  PYUI_DESKTOP_HEADLESS            1 for no window (needs a script)
  PYUI_DESKTOP_EXIT_AFTER_SCRIPT   1 to exit when the script ends
  PYUI_DESKTOP_SHOTS               screenshot folder

The run ends with SystemExit(0) from Controller.get_input (Esc, closing the
window, the end of a script). The device's controller_interface.unplayed lists
script steps not played yet.
