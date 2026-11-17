# Button Reader

A controller tester for every spruce device. It runs inside PyUI (`"pyuiEntry"`, see
`App/PyUI/docs/apps_in_pyui_readme.txt`) and reads every `/dev/input/event*` node raw, so it
shows the kernel's own codes.

**Apps → Button Reader.** For 3 seconds a start screen waits:

- press nothing: the **picture** opens. The face buttons are laid out by position, along with the
  D-pad, Select/Start, Menu/Home/Fn and both sticks with their deflection. The top row reads L3,
  L1 L2, the volume keys, R2 R1, R3 (no Power: pressing it puts the device to sleep). Every
  element is always drawn: what the device lacks (Home, Fn, a volume key, a stick, a stick click)
  is grayed out. Each control lights while it is held; the Fn box shows the Fn switch's position
  where there is one. Labels are PyUI's names for the codes, so on a board whose print differs
  from its position (the XU10), the bottom button can read "A". The first line under the picture
  names the device, or says "Unknown".
- press any button: the **full diagnostic**. Guided steps ask for each control the device has, by
  position (each step skips itself after 7 s), then the picture opens. A face step names the
  position and the letter printed there: `FACE_NORTH/X`, or `FACE_NORTH/Y` on an Xbox-style
  print (A bottom, B right, X left, Y top). Where spruce's `device_get_switch_position` reads a
  Fn switch (the TrimUIs), the last step asks for a flip: its action runs, so flip it back. At
  exit a report is written to `App/ButtonReader/reports/button-reader-<PLATFORM>-<n>.txt`, with
  `-retroarch.cfg` and `-sdl.txt` candidates beside it.

**Device info:** in the picture, hold L1 and R1 together for 5 seconds. The pane lists what the
manifest says and what this unit shows: its controls, each input source and the node standing for
it, and the display, panel, PyUI's scale, rumble, LEDs, RGB, Bluetooth, Wi-Fi, touch and lid. The
D-pad scrolls (left and right by a page); any other button closes it. Holding L1 + R1 never counts as the exit
hold.

**To leave:** hold any one button for 10 seconds (a countdown shows after 3), or press
Select and Start together. Select or Start alone does nothing. Don't press Power: spruce
puts the device to sleep.

spruce's own watchers keep running. A Menu tap sends RetroArch's menu key, and a Menu hold
runs the game-switcher action; neither leaves the app. On the A30, spruce's `joystickinput`
turns the stick into D-pad keys while PyUI runs; the app switches it to analog mode while it is
open (as spruce's PICO-8 and OpenBOR launchers do) and back to D-pad mode when it closes.

## Device manifests

`devices/<PLATFORM>.json` lists every control a device has, where its signal comes from and what it
lacks; Button Reader's rules come from it (format and provenance in `devices/README.md`). That is
how the Minis (no sticks) get no L3/R3 step while the Brick's Fn keys do (they send L3/R3), how the
A30's and the Smart Pro's sticks get no click step, how the Brick Pro gets a Home step its cfg
denies, and how the Minis' steps check codes their cfg leaves as placeholders. Where a manifest
marks measured stick axes `over_cfg` (the Flip, TrimUI and RGB30 right sticks, the XU Mini M's
down), they win over the cfg's lines, which spruce keeps. A device without a manifest is
"Unknown" and gets rules derived from its cfg.

## What is logged

At INFO, through PyUI's logger (`pyui.log`):

- every input node: its path, name, phys, sysfs path, bus ids, driver and device-tree node;
- each key's PyUI name, its cfg `B_*` variable, and the GPIO behind it, resolved from the
  device tree's `gpios` (e.g. `GPIO2_PA3`, with the Linux GPIO number when sysfs or debugfs
  gives the chip base). A virtual node fed by a daemon (TrimUI's `trimui_inputd`) is reported
  as "not GPIO-wired";
- every press and release; at exit, the axis ranges seen.

The report adds:

- the device, its manifest and each source with the node(s) matching it, and every code where the
  manifest and the cfg disagree;
- the device features the info pane shows;
- each axis's absinfo next to the range actually seen;
- per button, DT node and label → GPIO → kernel code → PyUI → cfg variable → RetroArch udev
  index → SDL joystick index;
- the guided steps' verdicts against the cfg;
- a candidate RetroArch autoconfig and an `SDL_GAMECONTROLLER_MAP` line (spruce's label-named
  form) built from the measured positions.

The numbering follows RetroArch v1.22.2's udev driver and SDL 2.28 / 2.32's Linux joystick driver.

## Desktop

On PyUI's DESKTOP device (`App/PyUI/docs/desktop_readme.txt`) the keyboard stands in for the pad:

- arrows: D-pad; X/Z/S/A: A/B/X/Y; Q/W: L1/R1; 1/2: L2/R2; C/V: L3/R3;
- Right Shift: Select; Enter: Start; M: Menu; - and =: the volume keys;
- T/F/G/H and I/J/K/L: the sticks; Esc: leave.

Reports then go to `<desktop data>/ButtonReader/`.
