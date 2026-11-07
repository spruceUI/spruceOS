<div align="center">

<img src="https://pokedaisy.com/og.png" alt="PokeDaisy: Game Boy, Game Boy Color, GBA and DS player with a live companion, on two screens or one, for Pokemon games and ROM hacks, free and open source" width="100%">

<h3>Pokémon, played better. Game Boy to DS, with a live companion, a widescreen overworld, a HUD and quick menu, and every chore one button away.</h3>

<p>
  <a href="https://github.com/lidor30/pokedaisy/releases/latest"><img src="https://img.shields.io/github/v/release/lidor30/pokedaisy?style=for-the-badge&label=release&color=2f81f7" alt="Latest PokeDaisy release"></a>
  <a href="https://github.com/lidor30/pokedaisy/releases"><img src="https://img.shields.io/github/downloads/lidor30/pokedaisy/total?style=for-the-badge&label=downloads&color=5c8a3c" alt="Total downloads"></a>
  <a href="https://discord.gg/vcmyKZZV5q"><img src="https://img.shields.io/badge/Discord-join-5865F2?style=for-the-badge&logo=discord&logoColor=white" alt="Join PokeDaisy on Discord"></a>
  <a href="https://www.reddit.com/r/PokeDaisy/"><img src="https://img.shields.io/reddit/subreddit-subscribers/PokeDaisy?style=for-the-badge&logo=reddit&logoColor=white&label=r%2FPokeDaisy&color=FF4500" alt="r/PokeDaisy on Reddit"></a>
</p>

<p>
  <strong><a href="https://github.com/lidor30/pokedaisy/releases/latest">Download</a></strong>
  · <strong><a href="#features">Features</a></strong>
  · <strong><a href="#supported-games">Supported games</a></strong>
  · <strong><a href="https://pokedaisy.com/docs/">Manual</a></strong>
  · <strong><a href="https://pokedaisy.com/feedback/#bug">Report a problem</a></strong>
</p>

<p>
  <sub><strong>Support PokeDaisy</strong></sub><br>
  <a href="https://www.patreon.com/cw/pokedaisy"><img src="https://img.shields.io/badge/Patreon-F96854?logo=patreon&logoColor=white" alt="Patreon"></a>
  <a href="https://buymeacoffee.com/lidor30g"><img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-FFDD00?logo=buymeacoffee&logoColor=black" alt="Buy me a coffee"></a>
  <a href="https://ko-fi.com/pokedaisy"><img src="https://img.shields.io/badge/Ko--fi-FF5E5B?logo=kofi&logoColor=white" alt="Ko-fi"></a>
</p>

</div>

PokeDaisy is a Game Boy, Game Boy Color, GBA and Nintendo DS player for Android handhelds with two screens or one,
made for the Pokemon games of every generation from Red to Black and popular ROM hacks. Next to the game runs a
live companion that reads it as you play: your party, bag, map, battle matchups, Pokedex and a spoiler-free guide,
all drawn in the game's own menu style.

- **Two screens** (AYN Thor, Retroid Pocket Duo, ...): the game on top, the companion on the bottom screen.
- **One screen** (Retroid Pocket 6, phones, ...): the companion opens as a window over the game or a panel beside
  it, and a HUD, a quick menu and battle buttons keep the essentials on the game screen.
- **DS games** (Platinum, HeartGold, SoulSilver, Black): the touch screen goes on the bottom screen, one tap swaps it for
  the companion.

## Devices

| Device                     | Status                                                         |
| -------------------------- | -------------------------------------------------------------- |
| AYN Thor                   | Tested, made for it                                            |
| Retroid Pocket Duo Lite    | Supported, with its own 4:3 layout                             |
| Retroid Pocket Duo         | Should work, not yet tested on real hardware                   |
| Anbernic RG DS             | Should work, not yet tested on real hardware                   |
| Retroid Pocket 6           | Single screen: tested                                          |
| Other one-screen handhelds | Should work, held sideways like the Pocket 6                   |
| Android phones (portrait)  | Should work, checked in screenshots only                       |
| A phone cast to a TV       | Should work: the game on the TV, the companion on the phone    |

Any Android 8.0+ device runs the games.

## Install

1. Download `PokeDaisy-<version>.apk` from the [latest release](https://github.com/lidor30/pokedaisy/releases/latest)
   on the device and open it (allow your browser or file manager to install apps if Android asks).
2. Open PokeDaisy. A short setup links your ROMs folders, picks where saves go (PokeDaisy's own folder or another
   emulator's, like RetroArch's) and can add cover art. All of it can be changed later in Settings.

The app updates itself: it offers each new version when you open it. The full manual is at
[pokedaisy.com/docs](https://pokedaisy.com/docs/) and in the app under Settings > HELP.

**No games are included.** Use your own legally dumped ROMs.

## Features

**The companion**

- **PARTY**: your team in your game's own party screen. Tap one for its summary: stats, moves, IVs / EVs,
  matchups, and which moves or TMs are worth learning.
- **BAG**: every pocket with icons and descriptions, and items you can use or give from it in the games that allow it.
- **BATTLE**: opens by itself. Your moves rated SUPER / RESISTED / NEUTRAL / IMMUNE, the foe's weaknesses,
  ability, item and stats, suggestions for who to send out and which move to use, and the rest of the foe's team.
- **MAP**: the game's region map with you on it, every place searchable, and FLY.
- **DEX**: seen / caught, full entries, evolutions, where to catch each one and the moves it learns.
- **GUIDE**: hints first, answers on a second tap. What's in the area you're in, the next boss's team, evolutions,
  tips and a STUCK? page.
- **CARD**, **STATES** (10 save-state slots), **ACHIEVEMENTS** (RetroAchievements), and the tabs you pick for the bar.
- **NUZLOCKE** (per game, GBA games but Emerald Rogue): keeps score of a Nuzlocke run, the first encounter in each
  area and every fainted Pokemon out for good, with a gravestone on its party slot.

**On the game screen**

- **HUD**: your party, a minimap, your Poke Balls and PC / BAG / WILD buttons while you walk around.
- **Quick menu** (L3): PC, FLY, BIKE, ROD, the keep-away spray, wild encounters on / off, save states.
- **Battle buttons**: FIGHT, POKEMON and RUN right beside the battle.
- **EXPAND**: the overworld drawn past the GBA's edges to fill a wide screen, with zoom and look-around.

**The player**

- Fast-forward (smart: normal speed in menus, fast in battles) with music that keeps its normal speed, slow motion,
  rewind, a real-time clock, save states, turbo buttons.
- Shaders (LCD, scanlines, CRT, GBA colours, edge smoothing), overlays, and your own RetroArch overlays.
- Makeovers: play one game as another game's hero, a Pokemon following you, day and night tints.
- Remappable controls and hotkeys, touch controls you can lay out yourself, Bluetooth and USB controllers.
- Optional cheats, wild encounters off, reusable TMs, auto-run and running indoors.
- A library with cover art, favorites, zipped ROMs, a dual-screen launcher, and launching from frontends like
  ES-DE, Cocoon and iiSU ([iiSU](docs/iisu/README.md), [ES-DE](docs/es-de/README.md) setup).
- Standard `.sav` / `.srm` saves, shared with mGBA and RetroArch. Every start keeps a backup of your save.
- English, Japanese, French, German, Italian, Spanish and Portuguese.

Everything is explained in the [manual](https://pokedaisy.com/docs/).

## Supported games

Any Game Boy, Game Boy Color, GBA or DS game plays. The companion needs one of the games below, **in the exact
version listed** (ROM hacks are recognized by their file, so another version
shows a "not supported" notice).

✅ works · ◐ partly · — not yet

| Game                           | Version                    | Party | Bag | Battle | Map |   Dex   | Guide |
| ------------------------------ | -------------------------- | :---: | :-: | :----: | :-: | :-----: | :---: |
| Red / Blue (GB)                | USA/Europe                 |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| PureRed / PureBlue (GB)        | 2.7.6                      |  ✅   | ✅  |   ◐    | ✅  |   ✅    |   —   |
| Yellow (GB)                    | USA/Europe                 |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Yellow (GB)                    | DE / FR / IT / ES          |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Gold / Silver (GBC)            | USA/Europe                 |  ✅   | ✅  |   ◐    | ✅  |   ✅    |   —   |
| Crystal (GBC)                  | USA, USA/Europe rev 1, AU  |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Crystal Clear (GBC)            | 2.5.11, 2.6.0 (4 builds)   |  ✅   | ✅  |   ◐    | ✅  |   ✅    |   —   |
| Prism (GBC)                    | 0.95 build 254             |  ✅   | ✅  |   ◐    | ✅  |   ✅    |   —   |
| Polished Crystal (GBC)         | 3.2.0-3.2.3 (16 builds)    |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| FireRed                        | USA/Europe, rev 0 and 1    |  ✅   | ✅  |   ✅   | ✅  |   ✅    |  ✅   |
| FireRed                        | ES / DE / FR / IT / JP     |  ✅   | ✅  |   ✅   | ✅  |   ✅    |  ✅   |
| LeafGreen                      | USA/Europe, rev 0 and 1    |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| LeafGreen                      | ES / DE / FR / IT / JP     |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Emerald                        | USA/Europe                 |  ✅   | ✅  |   ✅   | ✅  |   ✅    |  ✅   |
| Emerald                        | ES / DE / FR / IT / JP     |  ✅   | ✅  |   ✅   | ✅  |   ✅    |  ✅   |
| Ruby                           | USA, rev 0, 1 and 2        |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Ruby                           | ES/DE/FR/IT/JP, rev 0-1    |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Sapphire                       | USA, rev 0, 1 and 2        |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Sapphire                       | ES/DE/FR/IT/JP, rev 0-1    |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Platinum (DS)                  | USA rev 1                  |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| HeartGold (DS)                 | USA                        |  ✅   | ✅  |   —    | ✅  |   ✅    |  ✅   |
| SoulSilver (DS)                | USA                        |  ✅   | ✅  |   —    | ✅  |   ✅    |  ✅   |
| Black (DS)                     | USA/Europe                 |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Unbound                        | 2.1.1.1                    |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Unbound                        | 2.1.1.1 French             |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Radical Red                    | 4.1                        |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Gaia                           | 3.2                        |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Odyssey                        | 4.1.1                      |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Heart and Soul                 | 2.0.6                      |  ✅   | ✅  |   ✅   | ✅  |   ✅    |  ✅   |
| Amethyst                       | 1.3.0, 1.4.1               |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Celia's Stupid Romhack         | 1.1.4                      |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Orange Islands                 | Beta 5.7, an older beta    |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Ultra Violet                   | 1.22                       |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| FireRed Rocket Edition         | the one release            |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Ash Gray                       | 4.5.3, Fork Bug Fix 1.0    |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Ghost Grey                     | 1.0.1, 1.0.2, 1.0.4        |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Sword and Shield Ultimate Plus | 1.2.1.2 + its 3 patches    |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| GS Chronicles                  | 2.7.6                      |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Recharged Yellow               | 1.8.0, 1.9.0, 1.9.4, 1.9.7 |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Emerald Legacy                 | 1.1.4                      |  ✅   | ✅  |   ◐    | ✅  |   ✅    |  ✅   |
| Lazarus                        | 2.0                        |  ✅   | ✅  |   ◐    | ✅  |   ✅    |   ◐   |
| Emerald Seaglass               | 3.0                        |  ✅   | ✅  |   ◐    | ✅  |   ✅    |   ◐   |
| Too Many Types 2               | 1.5.2                      |  ✅   | ✅  |   ◐    | ✅  |   ✅    |   ◐   |
| Glazed                         | 9.2.0                      |  ✅   | ✅  |   ◐    | ✅  |   ✅    |   ◐   |
| Emerald Imperium               | 1.3.1                      |  ✅   | ✅  |   ◐    | ✅  |   ✅    |   ◐   |
| Quetzal                        | English Alpha 9 v0         |  ✅   | ✅  |   ◐    | ✅  |   ✅    |   ◐   |
| Quetzal                        | Spanish Alpha 9 v0         |  ✅   | ✅  |   ◐    | ✅  |   ✅    |   ◐   |
| Quetzal                        | Alpha 9 v1 (EN / ES)       |  ✅   | ✅  |   ◐    | ✅  |   ✅    |   ◐   |
| Quetzal                        | Alpha 0.8.4 (EN / ES)      |  ✅   | ✅  |   ◐    | ✅  |   ✅    |   ◐   |
| Moemon Quetzal                 | Alpha 0.8.4 Hotfix (EN/ES) |  ✅   | ✅  |   ◐    | ✅  |   ✅    |   ◐   |
| Super Mariomon                 | 1.2.1-1.3, 1.5.1, 1.5.2    |  ✅   | ✅  |   ◐    | ✅  |   ✅    |   ◐   |
| Recharged Emerald              | 2.2.5, 2.2.8, Rebalanced   |  ✅   | ✅  |   ◐    | ✅  |   ✅    |   ◐   |
| Elite Redux                    | 2.65.3b, 2.65.4.1b         |  ✅   | ✅  |   ◐    | ✅  |   ✅    |   ◐   |
| Team Rocket Dragonsden         | 1.5                        |  ✅   | ✅  |   ◐    |  ◐  |    —    |   ◐   |
| Wishes of Tomorrow             | 1.2.6                      |  ✅   | ✅  |   ◐    | ✅  |   ✅    |   ◐   |
| Dreamstone Mysteries           | the one release            |  ✅   | ✅  |   ◐    | ✅  |   ✅    |   ◐   |
| Emerald Rogue                  | 2.2.1-EX                   |  ✅   | ✅  |   ✅   | ✅  |   ✅    |   —   |
| SoulGold                       | 1.1.4, 1.2 (3 builds)      |  ✅   | ✅  |   ◐    | ✅  |   ✅    |   ◐   |
| R.O.W.E.                       | 2.1.9.1 Experimental       |  ✅   | ✅  |   ◐    | ✅  |    ◐    |   —   |

<details>
<summary><strong>Notes on the table</strong></summary>

For a version that isn't listed, the app tries to read it as a game it knows (BEST EFFORT) and asks you to pick
when it isn't sure. Map ◐ means place names only,
without the map picture. Guide ◐ means the live pages only (the wild encounters here and the next boss). Battle ◐
means the battle panes work but haven't been checked in every kind of battle. On the DS, HeartGold's and SoulSilver's
battles aren't read yet. Team Rocket Dragonsden is DragonsdenTV's Team Rocket Edition, not FireRed Rocket Edition.
With Wishes of Tomorrow's randomizer on, the guide and the Pokédex's AREA show the wild Pokémon your save meets.
The guides were written from each game's own data and may contain mistakes.

</details>

Want another game supported? Ask in [Game requests](https://github.com/lidor30/pokedaisy/discussions/categories/game-requests), and upvote the ones you want.

## Privacy

The app has no accounts, ads or analytics, and your games and saves never leave your device. It only goes online to
check for updates, fetch cover art or use RetroAchievements (only with your own key or sign-in), send a crash report
(only if you turn CRASH REPORTS on) and share a BEST EFFORT match (only if you tap SHARE: the ROM's hash, size and
game code, never the file). The website counts visits anonymously, with no cookies.

## Community and support

Come say hi, share your runs and ask questions on [r/PokeDaisy](https://www.reddit.com/r/PokeDaisy/) or
[Discord](https://discord.gg/vcmyKZZV5q). Found a bug? [Report it](https://pokedaisy.com/feedback/#bug).

PokeDaisy is free, with no ads and nothing locked. If it made a playthrough better, you can support it on
[Ko-fi](https://ko-fi.com/pokedaisy), [Patreon](https://www.patreon.com/cw/pokedaisy) or
[Buy Me a Coffee](https://buymeacoffee.com/lidor30g). It's optional, unlocks nothing and pays for PokeDaisy's own code
only: no games, ROMs or game content are sold or handed out.

## Building from source

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

A Linux build for handhelds (SDL2, the same mGBA core and the 3DS port's companion) is in early
testing: [linux/README.md](linux/README.md).

<details>
<summary><strong>AI tooling note</strong></summary>

This project may use AI-assisted development tools, such as Claude Code, to help with code generation, refactoring, and documentation. All changes are still reviewed by the maintainer and validated with the project's existing checks before release.

</details>

## Credits

<details>
<summary>mGBA, melonDS, rcheevos, fonts, shaders, the pret decomps, cover art sources</summary>

- [mGBA](https://mgba.io) by Vicki Pfau (endrift) and contributors runs the Game Boy, Game Boy Color and GBA games (MPL 2.0;
  source in [`third_party/mgba`](https://github.com/mgba-emu/mgba)), with its bundled blip_buf (LGPL 2.1) and inih (BSD).
- [melonDS](https://melonds.kuribo64.net) by the melonDS team runs the DS games (GPL 3.0; source in
  [`third_party/melonds`](https://github.com/melonDS-emu/melonDS), PokeDaisy's changes in
  [`third_party/patches`](third_party/patches)), with its bundled FatFs, Teakra (MIT), xxHash (BSD 2-Clause),
  tiny-AES-c (Unlicense), blip_buf (LGPL 2.1) and Dolphin's ARM64 emitter (GPL 2.0+).
- [rcheevos](https://github.com/RetroAchievements/rcheevos) by RetroAchievements.org (MIT) for achievements.
- [Pixel Operator](https://www.dafont.com/pixel-operator.font) font by Jayvee Enaguas (CC0), and
  [Atkinson Hyperlegible](https://www.brailleinstitute.org/freefont/) by the Braille Institute (OFL 1.1) for the manual's text.
- [PixelMplus](https://github.com/itouhiro/PixelMplus) (M+ FONT LICENSE, M+ FONTS PROJECT) for Japanese text, converted to Pixel Operator's pixel grid by `scripts/gen_jp_font.py`.
- The [pret](https://github.com/pret) decompilation projects (pokered, pokeyellow, pokegold, pokecrystal, pokefirered,
  pokeemerald, pokeruby, pokeplatinum, pokeheartgold), [pokeemerald-expansion](https://github.com/rh-hideout/pokeemerald-expansion)
  and [Polished Crystal](https://github.com/Rangi42/polishedcrystal)'s and [PureRGB](https://github.com/Vortyne/pureRGB)'s source, which the game data and guides were checked against.
- Screen shaders: LCD and scanlines from mGBA's (MIT), the GBA colours by Pokefan531 and hunterk, LCD PAPER after
  RetroArch's simpletex_lcd and zfast_lcd (GPL 2.0+), and libretro's xBR, xBRZ and ScaleFX for edge smoothing
  (MIT, xBRZ GPL 3.0).
- [PokeAPI](https://pokeapi.co) (BSD 3-Clause) for the National Dex species list.
- AndroidX, Jetpack Compose, Kotlin and Apache Commons Compress (Apache 2.0), XZ for Java (0BSD).

Every license is in [NOTICE](NOTICE) and, in the app, under Settings > LICENSES.
- Cover art from [SteamGridDB](https://www.steamgriddb.com) and its contributors, and box art from [RetroAchievements](https://retroachievements.org).

</details>

## License

PokeDaisy is free software under the [GNU GPL v3](LICENSE), with one
[additional term](NOTICE): if you share PokeDaisy or anything built from it,
keep the credit **"Based on PokeDaisy by Lidor Itzhari -
https://github.com/lidor30/pokedaisy"** in its documentation and credits.
Forks must stay open source under the same license.

PokeDaisy is a fan project, not affiliated with or endorsed by Nintendo,
Game Freak, Creatures or The Pokemon Company. Pokemon and all related names are
trademarks of their respective owners; Game Boy, Game Boy Color and Game Boy Advance
are trademarks of Nintendo. Device names (AYN Thor, Retroid, Anbernic) belong to their
makers, and RetroAchievements and SteamGridDB are independent services; none of them
endorse PokeDaisy. ROM hacks belong to their creators. No games, BIOS or game art are
included: use your own legally dumped ROMs.
