GVU API Keys
============

GVU uses two optional API keys to fetch subtitles and cover art.
Add your own keys to the files in this directory — they take priority
over any key compiled into GVU.

SubDL_API.txt
  Your SubDL API key for subtitle search.
  Get one free at: https://subdl.com/
  Format: paste the key on a single line, no extra text.

TMDB_API.txt
  Your TMDB API key (v3 read access token) for cover art.
  Get one free at: https://www.themoviedb.org/settings/api
  Format: paste the key on a single line, no extra text.

Notes:
- Keys in these files override any default key built into GVU.
- These files are never uploaded to GitHub or included in open-source builds.
- If a key file is missing or empty, GVU falls back to its built-in key.
- Subtitle search requires a SubDL key — without one, searches will fail
  because the Podnapisi fallback provider is no longer operational.
