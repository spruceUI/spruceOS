# Spruce Scraper

Box art for your games, downloaded on the handheld from [ScreenScraper](https://www.screenscraper.fr)
and saved where spruceOS looks for it.

Spruce Scraper is a spruceOS app built the way [Scrappy](https://github.com/gabrielfvale/scrappy)
works on muOS: [Skyscraper](https://github.com/Gemba/skyscraper) does the scraping, and a LÖVE app
(on [Aesthetic Spruce](https://github.com/CatalyticArkun/aesthetic-spruce)'s spruce runtime) shows
the progress. It is not affiliated with ScreenScraper, Skyscraper, Scrappy or Aesthetic.

> [!NOTE]
> Work in progress (v0.1.0-dev). It has run on one handheld so far, a TrimUI Smart Pro.

## What it does

- **Finds your systems the way spruce does.** It reads every `Emu/<system>/config.json`, looks in
  `Roms/<system>` and the folder names spruce also accepts (`snes`, `SNES`, ...), on the card and on
  a second card, and counts the games that have no box art yet.
- **Saves art in spruce's format.** Each image goes to `Roms/<system>/Imgs/<subfolder>/<game>.png`,
  named the way PyUI looks it up (every known extension removed: `Mario.nes.zip` → `Mario.png`).
  When you return to the menu, spruce converts the new images to QOI and makes its small copies, as
  it does after a Game Nursery download.
- **Picks the right region.** On *Auto*, a game named `(Europe)` gets the European box, `(Japan)`
  the Japanese one; games without a region in the name follow spruce's own region setting. You can
  also fix it to USA, Europe, Japan or World.
- **Uses every thread your ScreenScraper account allows.** Free accounts scrape with one thread;
  accounts that contribute to or support ScreenScraper get more, and Skyscraper reads the
  allowance from the account itself. You can also cap it at 1–4.
- **Shows what is happening:** a bar per system and for the whole run, the game being looked up,
  saved and not-found counts, threads in use, time left, and the last cover saved.
- **Only fills gaps by default.** Games that already have art are left alone. *Replace existing box
  art* downloads everything again and moves the old images to `Saves/SpruceScraper/replaced`.
- **Stops cleanly.** *Stop* lets the games in flight finish and saves the box art downloaded so
  far; when the daily ScreenScraper limit runs out it saves what it got and says so. The next run
  carries on with whatever is still missing.
- **Says what went wrong.** No connection, a wrong clock, a rejected login or a system Skyscraper
  could not finish each get their own message instead of a list of games "not found".

## Install

- **Game Nursery** (once the entry is published): *Game Nursery* → *Apps* → *Spruce Scraper*.
- **By hand:** unzip `SpruceScraper_vX.Y.Z_sd-overlay.zip` onto the root of the SD card so that
  `App/SpruceScraper` sits next to your other apps.

For 64-bit spruceOS 4.5+ devices: TrimUI Smart Pro / Smart Pro S / Brick / Brick Pro, Miyoo Flip,
Anbernic RG XX, MagicX Zero 28 / Zero 40 / XU20, GKD Pixel2, RGB30, Miniloong. It has been tested
on the TrimUI Smart Pro only so far. Not for the Miyoo A30 or the Mini family.

## Use

1. Connect to Wi-Fi.
2. Open *Spruce Scraper* from *Apps*.
3. Under *ScreenScraper account*, enter your user name and password (or put `username=...` and
   `password=...` lines in `App/SpruceScraper/screenscraper.txt` from a PC; it is read once at the
   next start). *Check account* shows how many threads the account allows.
4. Pick the *Systems* and *Box art region*, then *Scrape box art*.

Without an account Skyscraper scrapes anonymously: one thread and a small daily allowance, and
ScreenScraper turns anonymous users away when it is busy. A free account is enough to start.

## Files

| path | what |
|---|---|
| `Saves/SpruceScraper/settings.json` | your settings, including the ScreenScraper password in plain text (Skyscraper needs it on every run) |
| `Saves/SpruceScraper/skyscraper/.skyscraper/cache` | Skyscraper's downloads while a system is scraped; cleared once its images are saved |
| `Saves/SpruceScraper/replaced` | art moved aside by *Replace existing box art* |
| `Saves/SpruceScraper/logs` | the last five sessions |

## Credits and licence

Box art and data: ScreenScraper. Scraping: Skyscraper (GPL-3.0). Design: Scrappy (MIT).
spruce runtime and keyboard: Aesthetic (MIT). Full list: [docs/CREDITS.md](docs/CREDITS.md).

Spruce Scraper is MIT licensed ([LICENSE](LICENSE)); the bundled Skyscraper is a separate
GPL-3.0 program, and `.scraper/skyscraper/SOURCE.md` says where its source is.
