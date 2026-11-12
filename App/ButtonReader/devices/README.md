# Device manifests (`spruce-button-reader-device/1`)

One JSON file per spruce `PLATFORM` (`<PLATFORM>.json`). It lists every control the device physically
has, where each one's signal comes from (in terms Button Reader can see on the device) and what the
device lacks. Button Reader reads its rules from it:

- the guided steps: one per control listed, none for what is absent;
- the picture: what the device lacks is grayed out; the line under it names the device ("Unknown" without one);
- which daemon to switch (`fed_by: joystickinput` puts the A30's stick in analog mode while the app is open);
- which node a press should come from (a step notes a press from another node);
- the expected code where the cfg has none (the Miyoo Minis' cfg holds placeholders).

A device with no manifest falls back to rules derived from its cfg. `tools/diag/button-reader/check-manifests.py`
in the spruce wrapper checks these files against their cfgs.

## Top level

| key | type | meaning |
|---|---|---|
| `schema` | string | always `"spruce-button-reader-device/1"` |
| `platform` | string | spruce's `PLATFORM` value; equals the file name |
| `name` | string | `SPRUCE_DEVICE_NAME`, or the device's common name when the cfg has none |
| `brand` | string | maker |
| `models` | [string] | the retail devices this PLATFORM covers (an H700 bucket covers several) |
| `family` | string | `PLATFORM_FAMILY` (the cfg's folder: `tina-stock`, `darkmoss`, `h700`, `oakmoss`, `miyoomini`, `twig`) |
| `base` | string | what runs under spruce: `stock`, `BaseOS`, `dArkMoss`, `oakMOSS`, `twigUI-Next` (with the vendor where stock) |
| `soc` | string | e.g. `Allwinner A133P`, `Rockchip RK3566` |
| `arch` | string | `PLATFORM_ARCHITECTURE` (`armhf`, `aarch64`) |
| `identify` | string | how `helperFunctions.sh` picks this PLATFORM (cpuinfo string, os-release field, marker file) |
| `cfg` | string | the cfg path in spruceOS, e.g. `spruce/scripts/platform/tina-stock/A30.cfg` |
| `spruce_ref` | string | the spruceOS commit the cfg was read at (10 hex) |
| `face_print` | string | `"nintendo"` (B bottom, A right, X top, Y left) or `"xbox"` (A bottom, B right, X left, Y top) |
| `sources` | object | id -> source (below) |
| `controls` | object | slot -> control (below): every control the device has |
| `absent` | object | slot -> one-line reason the device lacks it |
| `evidence` | [string] | the captures and reports the facts came from (kept with the maintainers' lab evidence) |
| `notes` | [string] | anything a tester should know (optional) |

Every slot below appears exactly once, in `controls` or in `absent`:

- picture slots: `BOTTOM RIGHT TOP LEFT DPAD_UP DPAD_DOWN DPAD_LEFT DPAD_RIGHT L1 R1 L2 R2 L3 R3 SELECT START MENU HOME VOL_UP VOL_DOWN POWER`
  (face slots are positions: BOTTOM = cfg `B_B`, RIGHT = `B_A`, TOP = `B_X`, LEFT = `B_Y`);
- sticks: `LEFT_STICK RIGHT_STICK`;
- extras: `FN_SWITCH` (a latching switch), `FN_LEFT FN_RIGHT` (Fn keys that are not L3/R3), `LID`.

## Source

```json
"pad": {"kind": "virtual", "node": "MIYOO Pad1", "fed_by": "joypad", "from": "measured: A30-20260921.txt"}
```

| key | meaning |
|---|---|
| `kind` | `gpio-keys` (kernel gpio-keys / gpio-keys-polled), `adc-keys`, `joypad` (a kernel pad driver: singleadc/odroidgo/rocknix/adc-joypad), `mcu` (a kernel driver for a pad MCU, e.g. simplepad over UART), `pmic` (power key on the PMIC), `virtual` (a uinput node a daemon feeds), `uart` (a daemon reads a UART; no kernel input node of its own), `gpio` (read through sysfs/a spruce function, no input node), `hall` (lid sensor), `touch` |
| `node` | the input device name exactly as the kernel reports it (`/sys/class/input/eventN/device/name`); `null` for `uart`/`gpio` |
| `match` | optional extra names or `*` patterns that also count as this source (a name that changed between images) |
| `by_path` | optional `/dev/input/by-path/...` name spruce uses for it |
| `fed_by` | the daemon behind a `virtual` or `uart` source (`trimui_inputd`, `joypad`, `joystickinput`) |
| `device` | the UART or GPIO a `uart`/`gpio` source reads (`/dev/ttyS2`, `gpio243 PH19`) |
| `modes` | optional: signals that switch the daemon (`{"analog": "SIGUSR1", "keyboard": "SIGUSR2"}`) |
| `from` | provenance (below) |
| `note` | optional |

## Control

```json
"BOTTOM": {"code": "1 304", "source": "pad", "from": "cfg"}
"L3": {"code": "1 317", "source": "pad", "label": "Fn", "prompt": "Press the left Fn key (L3)", "from": "tester 2026-11-11"}
"LEFT_STICK": {"x": "3 0", "y": "3 1", "source": "pad", "from": "cfg"}
"FN_SWITCH": {"source": "fn-switch", "read": "device_get_switch_position", "from": "cfg (TrimUI .sh)"}
```

| key | meaning |
|---|---|
| `code` | the event as spruce's cfg writes it: `"1 305"` key, `"3 17 -1"` hat direction, `"3 2 255"` trigger axis |
| `x`, `y` | a stick's axes as `"3 <axis>"` with an optional sign, from `STICK_RIGHT[_2]` / `STICK_DOWN[_2]` |
| `also` | optional [codes] the same press also sends (MagicX's second codes) |
| `source` | a `sources` id |
| `label`, `prompt` | optional overrides for the picture label and the guided step's prompt |
| `read` | for a `gpio` control: the spruce function that reads it |
| `cfg_differs` | required when `code` (or a stick's `x`/`y`) differs from the cfg's value (or the cfg has none / says `DOESNT_EXIST`): why |
| `over_cfg` | sticks only, with `cfg_differs`: why the manifest's `x`/`y` are the hardware's. Button Reader then expects and draws those axes instead of the cfg's (the Flip, TrimUI and RGB30 right sticks, the XU Mini M's down; spruce keeps its cfg lines) |
| `models` | optional [model names from `models`]: only these models of the PLATFORM have it (the Mini Flip's lid, the Mini Plus's volume keys). Button Reader matches them against `SPRUCE_DEVICE_NAME`; when it can't tell the model, the control counts as unknown, not absent |
| `note` | optional |
| `from` | provenance |

## Provenance (`from`)

- `cfg`: the value as the cfg has it at `spruce_ref` (the default; the host test checks it);
- `measured: <file>`: seen on hardware (a Button Reader report, a discovery capture, a probe);
- `tester <YYYY-MM-DD>`: a tester with the device said so;
- `matrix`: the fleet controller matrix of 2026-09-06, which carries its own provenance;
- `derived: <why>`: inferred (same driver as a measured sibling, the device tree, a cfg comment); say from what.

Anything not verified on the device itself says so; never upgrade a derived fact to measured.
