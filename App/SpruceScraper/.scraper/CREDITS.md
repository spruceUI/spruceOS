# Credits

Spruce Scraper is not affiliated with ScreenScraper, Skyscraper, Scrappy or Aesthetic.

## Where it comes from

- **Scrappy** by Gabriel Vale — https://github.com/gabrielfvale/scrappy (MIT). The model for this
  app: Skyscraper as the scraping backend, run from a LÖVE app in background threads with a live
  progress view. Spruce Scraper's code is written for spruce rather than copied, but the approach is
  Scrappy's, as is the interim Skyscraper binary used in development (`skyscraper/INTERIM-SOURCE.md`).
  Support it: https://ko-fi.com/gabrielfvale
- **Aesthetic** by Jonathan Avila — https://github.com/joneavila/aesthetic (MIT), through its
  spruceOS port Aesthetic Spruce. `src/display.lua`, `src/gamepad_layout.lua`,
  `utils/check_lua_syntax.py`, the launcher, the crash handler, the per-device button table, the
  colour palette and the on-screen keyboard layout come from there, as do the LÖVE runtime files in
  `bin/` and `lib/` (not `lib/fallback/`). Support the original author: https://ko-fi.com/F1F51COHHT

## Data

- **ScreenScraper** — https://www.screenscraper.fr. Every image Spruce Scraper downloads comes
  from ScreenScraper's community database. Accounts that contribute or donate get more threads.

## Bundled programs and libraries

Inside spruceOS the licence texts this table names are not beside the files: they are in
`Licenses/SpruceScraper/` at the root of the card (`Licenses.7z` on a release card).

| component | use | licence |
|---|---|---|
| [Skyscraper](https://github.com/Gemba/skyscraper) by Lars Muldjord, maintained by Gemba | the scraper (`.scraper/skyscraper/Skyscraper`, a separate program) | GPL-3.0; its `SOURCE.md` says where the source is |
| [Qt](https://www.qt.io) 5.15 (qtbase, with the third-party code it carries) and [OpenSSL](https://openssl-library.org) 3.5 | linked into Skyscraper | LGPL-3.0 (Qt), Apache-2.0 (OpenSSL); texts and Qt's attributions in `.scraper/skyscraper/licenses` |
| [LÖVE](https://love2d.org) 11.5 and LuaJIT | the app runtime (`bin/`, `lib/`) | zlib (LÖVE), MIT (LuaJIT); `bin/LICENSE.txt` |
| `lib/fallback/*`: OpenAL Soft, mpg123, libmodplug, Ogg, Vorbis, Theora, libatomic | libraries LÖVE links against, used only where a board's firmware lacks them; built by spruce's 2.33 userland lane | LGPL-2.0+ (OpenAL Soft), LGPL-2.1 (mpg123), public domain (libmodplug), BSD-3-Clause (Xiph), GPL-3.0 with the GCC Runtime Library Exception (libatomic); `lib/fallback/PROVENANCE.md` |
| [Inter](https://rsms.me/inter/) | UI font | SIL OFL 1.1 (`assets/fonts/inter/OFL.txt`) |
| [json.lua](https://github.com/rxi/json.lua) by rxi | settings, system configs | MIT (`src/lib/json.LICENSE.txt`) |
| [Lucide](https://lucide.dev) `image-down` | app icon | ISC (`assets/icons/lucide/LICENSE.txt`) |
