# Netplay for NextUI and Spruce

Two-player LAN multiplayer between handhelds: shared-screen games, GB/GBC and
GBA linking, and experimental Nintendo DS local wireless. Connect through the
same Wi-Fi network or a handheld-hosted `netplay-XXXX` network where supported.
Network quality matters; an ad hoc network is not necessarily faster than a
house access point. Internet matchmaking is not implemented.

## Install

Back up your SD card before installing or updating.

- **NextUI:** install Netplay from the Pak Store, or extract
  `NextUI-Netplay-Complete.zip` into a new `Tools/<PLATFORM>/Netplay.pak/`
  folder on the SD card. The result is `Tools/<PLATFORM>/Netplay.pak/launch.sh`.
- **Spruce:** extract `Spruce-Netplay-Complete.zip` at the SD-card root.
  The result is `App/Netplay/launch.sh`.

Both archives include Netplay's compatibility cores, so nothing is downloaded.
No ROMs are included. On NextUI, DS play through DraStic needs NDS.pak from
the Pak Store; Netplay adds local wireless to it.

NextUI builds cover `tg5040` (TrimUI Brick, Smart Pro), `tg5050` (Smart Pro S),
`my282` (Miyoo A30), `my355` (Miyoo Flip) and `h700` (Anbernic RG XX family).
Spruce builds cover the TrimUI Brick, Brick Pro, Smart Pro and Smart Pro S,
Miyoo Flip, Miyoo A30, the Miyoo Mini family, the Anbernic H700 XX family and
spruce's dArkMoss devices (Powkiddy RGB30, RGB20SX, Miniloong Pocket 1 and
others). Hardware testing has been on the Brick, RG35XX H, A30 and Mini Flip;
other models are covered by their builds but untested. Details:
[Spruce coverage](docs/analysis/spruce-parity.md).

End any session and turn Netplay off before replacing the application folder.
Settings, saves, logs and backups live outside it: NextUI state in
`.userdata/shared/Netplay/`, Spruce state in `Saves/netplay/`.

## Play

1. Open Netplay, complete onboarding, and choose **Host** on one device.
   Choose the current Wi-Fi network or create an ad hoc network if offered.
2. Choose **Join** on the other device and select the host.
3. Exit the app and launch your games through the firmware's normal menu.
4. Use **X** in Netplay to end an active session. Wi-Fi is restored as needed.

A session continues while the app is closed. A host can accept a returning
peer without creating a new session. Sessions from a previous boot are cleaned
up when Netplay next checks them.

Starting a game offers an invitation to the peer when its firmware menu is
available. NextUI displays **A ACCEPT / B DECLINE** through Varnish, independently
of the optional START quick menu. Spruce offers **Play / Not now / Browse**.
Invitations identify a local ROM by its relative path; no ROM is transferred.
Invitations received during gameplay are ignored.

## Systems and modes

Netplay picks one core per system for each session. Each device tells the
other what it can run; the host chooses the first core in the list below that
both devices have and can play, and the weaker device decides how far down the
list that is. There are three tiers: 64-bit devices, the A30, and the Miyoo
Mini family. During a session the chosen core loads in place of the one the
firmware would use, so both players always run the same build. Players don't
choose cores. Every device and firmware pairing is worked out in
[the engine matrix](docs/engine-matrix.md).

| System | Cores, best first | Multiplayer |
| --- | --- | --- |
| FC/NES, FDS | FCEUmm | Shared screen |
| SFC/SNES | Supafaust, then Snes9x | Shared screen |
| MD/Genesis, Sega CD, 32X | PicoDrive | Shared screen |
| Master System, Game Gear | Genesis Plus GX (64-bit spruce pairs), Gearsystem, then PicoDrive | Shared screen |
| GB/GBC | Gambatte Dual, then Gambatte | Dual: both consoles on each device. Otherwise a link cable over the network |
| GBA | armGBA Together (A30 and up), armGBA Separate, mGBA Dual (64-bit), then gpSP | See below |
| PlayStation | PCSX ReARMed | Shared screen; not between a 64-bit NextUI device and a 32-bit one |
| NDS | DSperate, DraStic | Local wireless; experimental, no Download Play |

GBA modes:

- **armGBA Together** runs every console on both devices with shared inputs;
  each player sees their own. **armGBA Separate** links one console per
  device over the cable or Wireless Adapter. armGBA is spruce's core.
- **mGBA Dual** emulates both linked consoles on each device. On NextUI it
  comes from Netplay's bundled MGBA.pak, installed under **Extras > MGBA**.
- **gpSP** links over the Wireless Adapter, generation III Pokémon and
  Advance Wars 1 and 2 only. It is NextUI's default GBA core and the last
  resort. If a game needs more than gpSP can link, Netplay says which device
  should install mGBA.

Dual modes need both linked ROMs on each device for a two-cartridge session
(Pokémon Red with Blue). Without them the session falls back to the ordinary
link. Earlier builds (v4.0.0 and the betas) don't take part in core
selection; paired with one, each device uses its own core, as before.

On NextUI, **Configuration > Cores** lists Base and Extras systems. Each system
shows the core Netplay uses with a check and other installed cores as
available. Extras also installs Netplay's paks: **MGBA** (mGBA Dual),
**DSperate** (DSP.pak, games in `Roms/Nintendo DS (DSP)`) and **DraStic**
(local wireless added to NDS.pak, games in `Roms/Nintendo DS (NDS)`). Each
backs up what it replaces and can put it back or remove it.

Spruce has one **Cores** list, grouped by system, with the same checks. It
covers spruce's 64-bit and 32-bit RetroArch; a 64-bit device playing a 32-bit
one runs 32-bit RetroArch and cores for the session, so both run the same
build. Outside a session spruce's own emulator choices apply. DS local
wireless covers DraStic and DSperate; in a session on a 64-bit device Netplay
runs its own DSperate build, which links where spruce's 3.3 does not. DS on
the A30 and Mini family is untested.

For DS, start the same game and use its local wireless menu to create and join
a group. DraStic and DSperate use the same radio protocol, so either can play
the other. Performance depends on the game, device and network; measurements
are in [the DS notes](docs/nintendo-ds/dsperate.md).

## Configuration

- **Nickname:** the name shown to peers.
- **Cores:** which core Netplay uses per system, core options it keeps for
  sessions (gpSP's link type; armGBA's ports, timing and model on spruce),
  and on NextUI the paks Netplay installs.
- **Settings:** host protocol (LinkPlay or RetroArch), **Hybrid Network
  Traffic** (default **On**), compatibility cores and Disable Wi-Fi Power
  Saving. Protocol and hybrid changes apply to the next session.
- **Debug:** force compatibility cores, verbose debugging logs (default
  **Off**), session save backups (default **On**, the last three snapshots),
  checks and Wi-Fi restoration.
- **Turn Off Netplay:** end the session and remove emulator launch hooks.
  X ends the session while leaving hooks installed as ordinary passthroughs,
  ready for the next host/join. Neither action uninstalls cores.

Hybrid transport applies to LinkPlay: UDP carries inputs and hashes, with
redundancy and TCP retransmission; state transfers, serial link packets and
control remain reliable TCP. Turning it off keeps those inputs/hashes on TCP.
RetroArch protocol uses its own transport and does not support Netplay's
NETPACKET link modes.

NextUI also offers the Varnish quick menu and status icon, the GameSwitcher
shortcut, and Ad Hoc Network Switch where the device can host one.
Spruce hides these options and leaves Wi-Fi and sleep to its own firmware. The Spruce footer uses contextual button glyphs, B first,
with **B EXIT** at the main menu and **X END SESSION** while active.

Disable Wi-Fi Power Saving defaults off. H700 changes can reload the driver
and interrupt Wi-Fi briefly; the setting asks first and resets after reboot.

## Saves

In shared screen the host's save is authoritative and the guest cannot persist
its copy. Linked consoles keep their own saves. Frontend save states,
auto-resume, rewind and speed-changing features are blocked during sessions.
A player opening the emulator menu pauses the peer with a waiting message.
Peer loss offers Wait / Continue solo / Exit; a waiting or dimmed screen is
not proof of successful multiplayer.

## Build and test

See [release instructions](docs/release.md), [features](docs/features.md),
[Spruce coverage](docs/analysis/spruce-parity.md), and
[the test rig](testing/spruce/README.md). Historical reports describe the code
and harness at their recording time; changed fixtures do not rewrite old runs.

## Credits

- [NextUI](https://github.com/LoveRetro/NextUI) and Spruce/PyUI
- [mohammadsyuhada](https://github.com/mohammadsyuhada/nextui-netplay), original implementation
- [DSperate](https://github.com/beebono/DSperate), and josegonzalez's DS emulator paks
- Cheevos button-glyph implementation by Andrii Balakhtar (MIT; bundled license)
- My son, who wanted to trade Pokémon with me
