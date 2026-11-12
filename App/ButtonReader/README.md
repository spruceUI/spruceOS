# Button Reader

A controller tester for every spruce device. It runs inside PyUI (`"pyuiEntry"`, see
`App/PyUI/docs/apps_in_pyui_readme.txt`) and reads every `/dev/input/event*` node raw, so it
shows the kernel's own codes.

**Apps → Button Reader.** For 3 seconds a start screen waits:

- press nothing: the **picture** opens. The face buttons are laid out by position, along with
  the D-pad, Select/Start/Menu and both sticks with their deflection. The top row reads
  L3, L1 L2, the volume and power keys, R2 R1, R3. A one-stick device (the A30) shows no right
  stick and no R3. Each control lights while it is held. Labels are PyUI's names for the codes,
  so on a board whose print differs from its position (the XU10), the bottom button can read "A".
- press any button: the **full diagnostic**. Guided steps ask for each control by position
  (each step skips itself after 15 s; a device without sticks, like the Minis, gets no L3/R3
  step, except the Brick, whose Fn keys send L3/R3), then the picture opens. The Smart Pro's
  sticks don't click, so it gets no L3/R3 step either; the Brick Pro gets a Home step though its
  cfg says it has none. Where spruce's `device_get_switch_position` reads a Fn switch (the
  TrimUIs), the last step asks for a flip: its action runs, so flip it back. A face step names the position
  and the letter printed there: `FACE_NORTH/X`, or `FACE_NORTH/Y` on the XU10 (printed
  Xbox-style: A bottom, B right, X left, Y top). At exit a report is written to
  `App/ButtonReader/reports/button-reader-<PLATFORM>-<n>.txt`, with
  `-retroarch.cfg` and `-sdl.txt` candidates beside it.

**To leave:** hold any one button for 10 seconds (a countdown shows after 3), or press
Select and Start together. Select or Start alone does nothing. Don't press Power: spruce
puts the device to sleep.

spruce's own watchers keep running. A Menu tap sends RetroArch's menu key, and a Menu hold
runs the game-switcher action; neither leaves the app. On the A30, spruce's `joystickinput`
turns the stick into D-pad keys while PyUI runs; the app switches it to analog mode while it is
open (as spruce's PICO-8 and OpenBOR launchers do) and back to D-pad mode when it closes.

## What is logged

At INFO, through PyUI's logger (`pyui.log`):

- every input node: its path, name, phys, sysfs path, bus ids, driver and device-tree node;
- each key's PyUI name, its cfg `B_*` variable, and the GPIO behind it, resolved from the
  device tree's `gpios` (e.g. `GPIO2_PA3`, with the Linux GPIO number when sysfs or debugfs
  gives the chip base). A virtual node fed by a daemon (TrimUI's `trimui_inputd`) is reported
  as "not GPIO-wired";
- every press and release; at exit, the axis ranges seen.

The report adds:

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
