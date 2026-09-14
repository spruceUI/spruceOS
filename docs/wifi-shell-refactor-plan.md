# WiFi: shell owns the radio

Plan for moving every WiFi action out of PyUI into spruce's shell scripts.
Branch: `refactor/wifi-shell-owns-radio`, cut from Development at `ce04b7e9f`.

## Status

Implemented on the branch. **Nothing has been run on hardware yet**; the shell
pieces were only stub-tested on a PC (lock ordering, queued toggles, stale lock,
connect parsing, conf repair, watchdog timing).

| Phase | Commit |
|---|---|
| 1. `wifi.sh`, connect/forget hooks, conf repair | `b8dc7393a` |
| 2. Shell callers go through `wifi.sh` | `2e80f904a` |
| 3. PyUI toggle and connect: Flip, A30, Mini, TrimUI, Anbernic XX, Miniloong | `0a948ac9e` |
| 4. `wifi_watchdog.sh` replaces `monitor_wifi` | `37d4461b5` |
| 5. RGB30, Mini boot script, adbd app | `e1c8aef37` |
| 6. Cleanup: dead stubs and helpers, failed signal reads show no signal | last commit |

Where the questions at the end are still open, this is what was built:

- **Watchdog:** kept, with the old monitor's rules. It is off on the Anbernic XX line
  (never had one), the Mini (a restart re-powers the chip) and wherever the OS
  owns the radio (RGB30, Pixel 2).
- **`.wifi`:** PyUI keeps writing it.
- **Connect feedback:** unchanged; the status row shows the address or
  "Connecting". `/tmp/wifi_state` is written but PyUI does not read it yet.
- **Pixel 2:** the shell treats the OS as owning the radio, and the connman calls
  PyUI's toggle and menu used to make now live in `Pixel2.sh` hooks
  (`device_wifi_power_on`/`_off` wrap rfkill with the connmanctl calls,
  `device_wifi_connect` resolves the service id and writes the config file).
  Untested on hardware; the stack question is still open.
- **Single-network forget:** not added.

Changes from the plan below:

- `device_wifi_connect` takes the password as an argument. PyUI pipes the SSID
  and password to `wifi.sh connect` on stdin and knows no file protocol; the
  front process stores them in a private `/tmp/wifi_connect.$$` for its worker,
  which reads and deletes it before anything else. Only the RGB30's `nmcli` and
  the Pixel 2's `connmanctl` see the password on a command line, as before.
- TrimUI's PyUI class no longer kills `wpa_supplicant` at power off and reboot:
  `save_poweroff.sh` runs `device_prepare_for_poweroff`, may still need WiFi for
  the Syncthing shutdown sync, and kills the supplicant itself before the unmount.
- `WifiMenu.reload_wpa_supplicant_config`, an uncalled `wpa_cli reconfigure`, is
  gone; the menu has no way left to talk to the supplicant except through
  the scanner's reads.
- In-game WiFi off is now a full `suspend`. Before, it killed the supplicant and
  only cut power when connected. On the XX line the driver is now unloaded until
  game exit.
- PyUI calls `wifi` by name, never by path. `spruce/scripts/bin/wifi` execs
  `wifi.sh`, and every platform cfg puts `spruce/scripts/bin` first on PATH.
- `clearwifi.sh` stays as a one-line wrapper, so the task list entry is unchanged.
- The Mini's `device_wifi_power_off` only relies on `ifconfig down`, as PyUI did.
  `axp_test wifioff` was not added without a device to check it on.

### Hardware checks for this branch

On top of **Must not regress** below:

- **All devices:**
  - Toggle WiFi five times quickly; it ends in the last state shown.
  - Join a network whose password has spaces or quotes.
  - Try a wrong password.
  - Forget all.
  - Check `/mnt/SDCARD/spruce/scripts/bin/wifi status` over SSH (SSH shells
    don't load the platform cfg, so `wifi` alone isn't on their PATH).
  - Check spruce.log for `wifi.sh:` lines.
- **TrimUI and Flip:** sleep with WiFi on, then wake. Repeat with a USB dongle.
- **Any device:** set in-game WiFi off, launch a game, exit, and WiFi comes back.
- **Mini Plus or Mini Flip:** cold boot with WiFi on, toggle off then on, and join a
  network.
- **RGB30:** join from the list, toggle, and a game exit keeps WiFi off.
- **Pixel 2:** toggle off and on, join a network, wrong password. Nothing on this
  device has been run since the connman calls moved into `Pixel2.sh`.
- **Watchdog (Brick Pro or Flip):**
  - Turn the router off; a restart is logged about every minute, up to five.
  - Turn the router back on; WiFi reconnects.
  - During sleep there are no restarts.

## Goal

PyUI shows WiFi and asks for input. It does not start or stop `wpa_supplicant`
or a DHCP client, load drivers, write power rails, write `wpa_supplicant.conf`,
or restart WiFi on its own. Every WiFi action is one call to a shell entry point,
which returns immediately.

Why: most of the bugs found in the 2026-09-13 audit came from PyUI and the shell
both driving the radio. Examples: the shell unloads the XX driver and PyUI's
toggle cannot load it back; PyUI's monitor turns WiFi off while the shell turns it
on; the Flip's PyUI kills the connection the shell is bringing up at boot.

## Ground rules

- **The saved setting is the only source of truth for on/off**: `.wifi` in
  `$SYSTEM_JSON`. Every action ends by making the radio match it.
- **One lock** around every radio change, shell or PyUI initiated.
- **Per-device behaviour lives only in platform hooks** (`device_wifi_power_on`,
  `device_manages_own_wifi`, ...). No per-device WiFi logic in PyUI.
- **PyUI may read state** (IP, signal, scan results) for display. Reads never
  change anything.
- **POSIX sh only.** No `flock` (not shipped for the 32-bit A30/Mini), no bashisms,
  no `ifconfig` on hosts without net-tools, no `pgrep -x`.

## Where things stand

### Shell (spruce/scripts)

- `enable_wifi` / `disable_wifi` (helperFunctions.sh:1215, :1299) do the real work
  through platform hooks. They have **no lock**, and about ten paths call them,
  several backgrounded: boot (`runtime.sh:47 &`), game exit
  (`standard_launch.sh:223 &`), wake hooks, the switch (`scene-wifi.sh`), USB
  hot-plug, `clearwifi.sh`, shutdown, and PyUI.
- `enable_wifi` ignores the result of `device_wifi_power_on` and
  `device_ensure_wifi_interface`, so it carries on with no `wlan0`.
- `/tmp/wifion` and `/tmp/wifioff` are written but only read by `bugReport.sh`.
- Missing entirely: a single entry point, connect to an SSID, forget one network,
  a link monitor, and a status query.
- `check_and_connect_wifi` (game launch, Splore, shutdown) forces `restart_wifi`
  and draws a waiting screen. The shutdown caller doesn't check `.wifi`.
- The only lock pattern in the repo is `mkdir`, with a pid for stale detection:
  `networkservices.sh:20-56` and `applySetting/networkServiceToggle.sh:96-126`.
  The latter re-execs itself detached so PyUI isn't kept waiting.

### PyUI (App/PyUI/main-ui)

| Device | Toggle | Boot | Monitor thread | Connect |
|---|---|---|---|---|
| Flip | Python bring-up (rail, supplicant, udhcpc); shell only with a dongle | stops and restarts WiFi if a ping fails | yes, if `enableWifiMonitor` | Python writes the conf block |
| A30 | Python bring-up | conf repair | always | Python |
| Mini Plus / Flip | Python: `insmod 8188fu`, `axp_test wifion`, supplicant, udhcpc | brings WiFi up itself, ignores `include_wifi` | no | Python |
| Brick / Brick Pro / Smart Pro | Python; shell only with a dongle | stops and restarts WiFi | always | Python |
| Smart Pro S | Python | monitor does it | always | Python |
| Anbernic XX, RG28XX | shell, via a Python-side lock | conf repair | no | Python |
| RGB30 | `nmcli radio` | none | no | `nmcli device wifi connect`, synchronous on the UI thread |
| Miniloong | Python threads | monitor does it | if `enableWifiMonitor` | `wpa_cli add_network` + udhcpc |
| Pixel 2 | `connmanctl` | none | always, and it crashes on first restart | connman config file + connect |

Also in PyUI:
- `ensure_wpa_supplicant_conf` repairs a broken conf; the shell only creates a
  missing one.
- The scanner's `wpa_cli` error sets a flag that makes the monitor restart WiFi.
- "Forget all WiFi networks" runs `clearwifi.sh` through `subprocess.run`, which
  blocks the menu.
- `changeCmd` settings run their script synchronously, so they don't suit a
  WiFi bring-up that can take a minute.

## Target design

### `spruce/scripts/wifi.sh`

One entry point. Called by PyUI and by every shell path that changes the radio.

| Command | Does | Callers |
|---|---|---|
| `apply` | Make the radio match `.wifi`: `enable_wifi` or `disable_wifi` | boot, game exit, wake, switch, hot-plug, PyUI toggle, connect/forget |
| `connect` | Read the SSID and password from `/tmp/wifi_request/connect`, remove the file, store the network through `device_wifi_connect`, then `apply` | PyUI network picker |
| `forget-all` | Clear saved networks through `device_wifi_forget_all`, then `apply` | "Forget all WiFi networks" task |
| `restart` | If `.wifi` is 1: `disable_wifi`, `enable_wifi` | link watchdog |
| `suspend` | Radio off **without** touching `.wifi`; writes `/tmp/wifi_suspended` | sleep entry, in-game WiFi off, shutdown |
| `status` | Prints `key=value` lines; no lock, no side effects | PyUI (optional), bug report |

Mechanics, following `networkServiceToggle.sh`:

- **Hand-off.** Without `--worker`, it runs `sh "$0" <command> --worker &` and
  exits, so callers never block. `--wait` runs the worker in the foreground for
  callers that must finish first: sleep entry and shutdown.
- **Lock.** `mkdir /tmp/spruce_wifi.lock`, with the holder's pid inside. The lock
  counts as stale when `/proc/<pid>/cmdline` no longer contains `wifi.sh`, the
  check `networkservices.sh` uses to survive pid reuse. Waiting gives up after
  300 s; the XX SDIO recovery alone can take about 75 s.
- **Latest setting wins.** The worker reads `.wifi` after it gets the lock, not
  when it was called. A burst of toggles lands on the last one, which also
  removes the Python-side lock the XX class uses today.
- **Result.** It writes `/tmp/wifi_state` (`off`, `on`, `no_radio`, `failed`),
  so PyUI can show why WiFi isn't up without probing hardware. `enable_wifi`
  returns non-zero when power-on or the interface check fails, instead of
  carrying on.
- **Passwords never appear** in argv, logs or `ps`. PyUI pipes the network on
  stdin; `wifi.sh` keeps it in a 0600 file only between its front process and
  its worker, which deletes the file before doing anything else.

### Who writes `.wifi`

PyUI keeps writing it. It already owns and caches that file, and every other
PyUI setting works this way. The switch (`scene-wifi.sh`) keeps writing it too.
Both then call `wifi.sh apply`. The shell only reads `.wifi`, apart from the
switch.

### Hooks

Existing hooks stay as they are. New ones, with defaults in `platform/device.sh`:

| Hook | Default | Overridden by |
|---|---|---|
| `device_wifi_connect <ssid> <password>` | replace the SSID's block in `$WPA_SUPPLICANT_FILE`, then `wpa_cli -i wlan0 reconfigure` and select it | RGB30 (`nmcli device wifi connect`), Pixel 2 |
| `device_wifi_forget_all` | today's `clearwifi.sh` wpa branch, legacy confs included | RGB30 (delete `802-11-wireless` profiles), Pixel 2 |
| `device_wifi_watchdog_enabled` | yes when spruce manages WiFi | no on RGB30 and Pixel 2 |

Conf repair (empty file, no `ctrl_interface`, unbalanced braces: move it to
`.broken` and rewrite) moves from `MiyooTrimCommon.wpa_conf_problem` into
`enable_wifi`'s conf check.

### Link watchdog

`spruce/scripts/wifi_watchdog.sh`, started with the other watchdogs where
`device_wifi_watchdog_enabled` says yes. It uses today's PyUI monitor policy:

- healthy means `wlan0` has an address, or there is no saved network
- after 60 s unhealthy: `wifi.sh restart`, up to 5 times, then wait 10 minutes
- never writes `.wifi`

It pauses while `/tmp/sleep_helper_started` or `/tmp/wifi_suspended` exists, so it
never fights sleep or the in-game WiFi-off option. That's the case PyUI's
monitor never had to handle, because it only ran while the menu was open.

**Open question:** whether spruce needs a watchdog at all. The XX line has run
without one. See the questions below.

### PyUI after the refactor

- **`DeviceCommon.enable_wifi` / `disable_wifi`:** one implementation for every
  device. Save `.wifi`, launch `wifi.sh apply`, `note_wifi_change()`. Per-device
  overrides are removed.
- **`DeviceCommon.wifi_connect`:** pipe the SSID and password to
  `wifi.sh connect`.
- **"Forget all WiFi networks":** the task runs `wifi.sh forget-all`, which
  returns at once, so the menu no longer blocks.
- **Status stays in PyUI as reads:** `get_ip_addr_text`, signal, scan list,
  `wpa_cli status`. It adds `/tmp/wifi_state` for "no radio" and "failed".
- **Removed:**
  - `monitor_wifi` and its threads (Flip, A30, four TrimUI, Miniloong, Pixel 2, muOS)
  - `restart_wifi_services`, `start_wifi_services`, `stop_wifi_services`,
    `start_wpa_supplicant`, `start_udhcpc`, `set_wifi_power`
  - the WiFi parts of every `startup_init`
  - `ensure_wpa_supplicant_conf`, `_write_wpa_supplicant_block`
  - the scanner-error-triggers-restart path
  - the three copies of the USB dongle check (Flip, TrimUI, RG28XX)
  - the XX `_run_shell_wifi` lock
- **Stays:** RG28XX `supports_wifi` (it only reads the shell's markers), and
  RGB30 `is_wifi_enabled`, which reads `.wifi` instead of rfkill.

## Caller changes

### Shell

| Today | After |
|---|---|
| `runtime.sh:47` `enable_or_disable_wifi_per_system_json &` | `wifi.sh apply` |
| `emu/standard_launch.sh:223` same, at game exit | `wifi.sh apply` |
| `trimui_a133p.sh`, `SmartProS.sh`, `Flip.sh` wake hooks | `wifi.sh apply` |
| `trimui_a133p.sh:55`, `SmartProS.sh:419` `disable_wifi` at sleep | `wifi.sh suspend --wait` |
| `SmartProS.sh:444` `disable_wifi` at poweroff | `wifi.sh suspend --wait` |
| `FN_Button/scene-wifi.sh` writes `.wifi`, then enable/disable | writes `.wifi`, then `wifi.sh apply` |
| `usb_wifi_dongle.sh` hot-plug `enable_wifi`, blocking the watchdog loop | `wifi.sh apply` |
| `tasks/clearwifi.sh` | `wifi.sh forget-all` |
| `emu/lib/network_functions.sh` in-game WiFi off (kills, power off, flags untouched) | `wifi.sh suspend`; game exit's `apply` clears it |
| `check_and_connect_wifi` → `restart_wifi` (in-game services, Splore) | `wifi.sh apply --wait` when `.wifi` is 1; never switch WiFi on against the setting |
| `save_poweroff.sh:247` Syncthing connect | gated on `.wifi` |
| `platform/miyoo_mini_startup.sh:40-48` own bring-up | `wifi.sh apply` |
| `App/adbd/launch.sh` own supplicant | `wifi.sh apply`, honouring the setting |
| `RGB30.sh` `rgb30_wifi_up` dev path | gated on `.wifi` |

### PyUI

| Today | After |
|---|---|
| `MiyooTrimCommon.enable_wifi` / `disable_wifi` | `DeviceCommon` version, `wifi.sh apply` |
| Flip `enable_wifi`, `set_wifi_power`, `restart_wifi_services`, `startup_init` WiFi | removed |
| Mini `start_wifi_services`, `set_wifi_power` | removed; the bring-up moves to Mini hooks |
| TrimUI `enable_wifi` dongle hand-off, `_wpa_supplicant_quit` | removed |
| XX `enable_wifi` / `disable_wifi` / `_run_shell_wifi` | removed |
| RGB30 `enable_wifi` / `disable_wifi` / `wifi_connect` | removed; the RGB30 hooks do this |
| Miniloong `enable_wifi` / `disable_wifi` / `wifi_connect` threads | removed |
| GKD `enable_wifi` / `disable_wifi`, connman menu connect | removed; the Pixel2.sh hooks carry the connman calls (untested) |
| `DeviceCommon.wifi_connect` | stdin + `wifi.sh connect` |
| `monitor_wifi` everywhere | removed once `wifi_watchdog.sh` lands |

## Per device

| Device | Shell work needed | Notes |
|---|---|---|
| Flip | none beyond the common work; rail and dongle hooks already exist | keep the #1653 dongle behaviour |
| A30 | none; power hooks are correctly no-ops | `ps -f` and `pgrep -x` traps |
| Mini Plus / Mini Flip | new `device_wifi_power_on` (`insmod 8188fu`, `axp_test wifion`, wait for `wlan0`) and `_off` (`ifconfig down`, plus `axp_test wifioff` and `rmmod` if they exist; verify on hardware) | OG/V4 already answer "no radio" |
| Brick / Brick Pro / Smart Pro | none beyond the common work | dongle contract stays |
| Smart Pro S | `device_ensure_wifi_interface` waiting for `wlan0` (`aic8800_fdrv` loads in a background subshell at boot) | |
| Anbernic XX, CubeXX | `device_has_wifi_radio` honouring `/tmp/wifi_unavailable` | already shell-driven |
| RG28XX | none | keep `supports_wifi` marker reads |
| RGB30 | `device_wifi_connect` and `device_wifi_forget_all` over nmcli; watchdog off | NetworkManager owns WiFi; no `ifconfig` |
| Miniloong | none beyond the common work | fix `startup_init` signature |
| Pixel 2 | `device_manages_own_wifi`; power and connect hooks carry the old connman calls; forget still goes to the nmcli branch | decide connman vs NetworkManager, then fix whichever hook is wrong |
| Zero28 | nothing new | has no PyUI class, so it only gets the shell side |
| muOS / Rocknix classes | none | PyUI keeps its no-op overrides; removing the monitor stops the stray udhcpc |

## Phases

Each phase is one commit or a small series, tested on hardware before the next.
Devices on hand: RG35XXSP, CubeXX, RG28XX, Brick Pro, TSPS, Smart Pro, RGB30;
Flip, A30 and Mini Flip per earlier sessions.

1. **Shell foundations, not wired in.** `wifi.sh` with all commands, the lock,
   `/tmp/wifi_state`, `enable_wifi` return codes, conf repair, and the default
   connect and forget hooks. Nothing calls it yet.
   - Local stub tests.
   - On a Brick Pro and an RG35XXSP over SSH: run each command, including
     overlapping `apply` runs.
2. **Shell callers go through `wifi.sh`.** Boot, game exit, wake, sleep, switch,
   hot-plug, forget, shutdown, in-game off, the Mini startup script, adbd.
   - Brick Pro: sleep/wake, dongle both ways, switch.
   - RG35XXSP: boot, first boot.
   - TSPS: sleep/wake.
3. **PyUI toggle and connect use `wifi.sh`** for XX, TrimUI, Flip and A30. Delete
   their PyUI bring-up, conf writing and boot WiFi code.
   - Toggle, join a network, wrong password, forget all.
   - RG35XXSP, Brick Pro, TSPS, Flip, A30.
4. **Watchdog replaces `monitor_wifi`.** Add `wifi_watchdog.sh`; delete PyUI's
   monitor and the scanner restart path.
   - Router with no internet: WiFi stays on.
   - Pull the AP: it recovers when the AP returns.
   - Game with in-game WiFi off: no fighting.
5. **The rest.**
   - Mini power hooks.
   - Miniloong.
   - RGB30 connect/forget hooks and `is_wifi_enabled` from `.wifi`.
   - Pixel 2 after the stack decision.
6. **Cleanup.** Dead stubs and duplicate dongle checks; unify signal read failures
   to -200.

## Must not regress

Hardware-verified or shipped on 2026-09-13; check each again in the phase that
touches it.

- XX toggle off then on reloads `8821cs` and gets an address (RG35XXSP).
- First boot of a fresh install comes up with WiFi off on every device; every
  shipped `*-system.json` has `"wifi": 0`.
- TrimUI wake reconnects (Brick Pro).
- Dongle in with WiFi off, then on: connects on the dongle. Dongle out with WiFi
  off, then on: back on the onboard radio (Brick Pro).
- Forget all, then the network list still scans (Brick Pro).
- RG28XX with no dongle hides WiFi; OG Mini/V4 never start WiFi.
- RGB30: spruce never starts a supplicant beside NetworkManager; WiFi off survives
  a game exit.
- `networkservices.sh` still starts SSH/Samba/Syncthing after a connect.
- The PyUI monitor never switches WiFi off (until the watchdog replaces it).

## Questions for the team

1. **Watchdog at all?** Keep a shell link watchdog, or rely on boot, wake and game
   exit? Recommendation: keep it for spruce-managed WiFi. The Flip and TrimUI
   rely on today's monitor to recover from AP drops.
2. **`.wifi` writer.** PyUI keeps saving the setting and the shell only applies it.
   OK, or should `wifi.sh on|off` write it too?
3. **Connect feedback.** Is showing `/tmp/wifi_state` plus the address enough, or
   should connect report a wrong password? That needs `wpa_cli status` or event
   parsing in the shell.
4. **Pixel 2.** connman or NetworkManager? Today the shell starts NetworkManager
   and iwd while PyUI drives connman.
5. **Single-network forget.** Out of scope, or add `wifi.sh forget <ssid>` while
   we're here?

## Out of scope

- Bluetooth.
- The Zero28 PyUI class.
- muOS and Rocknix beyond keeping them out of spruce's WiFi paths.
- The other audit findings (switch boot apply, conf atomic write,
  passwords in timeout logs) unless a phase touches that code.
