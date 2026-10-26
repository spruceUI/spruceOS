# Saturn standalone pad seeds

**UNVERIFIED.** Every file here was generated from the boards' platform cfgs without a check on a device. The user
asked for this on 2026-10-16: "ship an auto-generated control map without verification for test purposes to kick off
the control audit in a later phase". Each keymap entry carries `"spruce_generated": "unverified-2026-10-16"`. Drop
the tag from a table once a device run has confirmed it.

## What the files do

The standalone (`Emu/SATURN/yabasanshiro`) only plugs in a Saturn pad when `keymapv2.json`'s `player1` names the
live pad exactly: instance id, SDL name and GUID. Its menu button comes from
`.emulationstation/es_temporaryinput.cfg`.

A board opts in by exporting `SATURN_PAD_TABLE` from its platform cfg. At each launch, `seed_yaba_pad` in
`spruce/scripts/emu/lib/yaba_functions.sh` does three things:
- points `player1` at `keymap-<table>.json`'s pad;
- adds that table's entry when it is missing or was seeded from another table, so binds changed inside the emulator
  stay;
- replaces the pad's entry in `es_temporaryinput.cfg` with `es-<table>.xml`.

This folder is not in spruceBackup, so updates refresh it. The live `keymapv2.json` is backed up, and
"Reset YabaSanshiro config" restores it from `default_configs`. The next launch re-seeds the board's entry.

## Layout

The libretro core's Saturn layout:
- Saturn A on the bottom button (B label), B on the right (A label), X on the left (Y label), Y on the top (X label).
- C/Z on L1/R1, L/R on L2/R2, and Start.
- Menu (spruce's B_MENU) opens the standalone's menu. The RGB30 has no menu key: L3 does it, or R3 with Button
  Settings > Menu button.

## Tables and where their pad names come from

| Table | Pad | Identity |
|---|---|---|
| Zero28, Zero40, XU20 (+ `-riders`) | magicx-input | GUID measured from the standalone's log (2026-10-15) |
| Miniloong | retrogame_joypad | measured (2026-10-15) |
| RGB30, RGB30-R3, RGB20SX | retrogame_joypad | computed: the Miniloong's pad ids |
| A10Mini | GO-Super Gamepad | computed |

"Computed" means the cfg's SDL map GUID with SDL's name CRC (CRC-16/ARC of the evdev name) in bytes 2-3. That rule
gives the measured GUID on every pad measured so far. The Pixel 2 has no SDL map, so it has no table. The G350
and XU Mini M are left out on purpose (user, 2026-10-16: "Leave out everywhere", as for their 10-15 deferral).

## Regenerating

`docs/research/saturn-controls-20261015/scheme/gen_saturn_pads.py <spruceOS tree>` in the CFW/Spruce wrapper writes
these files from the cfgs (`--check` compares). `scheme/test_seed.sh` tests the launch step under busybox.
