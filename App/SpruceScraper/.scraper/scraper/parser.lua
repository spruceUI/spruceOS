--- Skyscraper output -> events
---
--- Patterns cover Skyscraper 3.17 (Scrappy's build) and 3.21 (src/skyscraper.cpp,
--- src/scraperworker.cpp, src/screenscraper.cpp); the two word some thread messages differently.
--- Every line becomes one event; lines nothing matches are { kind = "log" }.
local util = require("scraper.util")

local parser = {}

local function hms(h, m, s)
	return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
end

-- { pattern, reason } for runs ScreenScraper (or Skyscraper) ended early
local STOPS = {
	{ "daily ScreenScraper request limit has been reached", "quota" },
	{ "ScreenScraper API is currently closed", "closed" },
	{ "apparently been blacklisted at ScreenScraper", "blacklisted" },
	{ "This is NOT going well", "failing" },
	{ "very little disk space left", "space" },
}

-- What Skyscraper prints before it gives up on a run (3.17 and 3.21 wordings); a run that ends
-- badly without one of these is reported by its exit code (scraper/pipeline.lua)
local ERRORS = {
	"Couldn't read artwork xml file",
	"Cannot read artwork xml file",
	"Parsing artwork XML",
	"cannot continue",
	"Please set a valid platform",
	"Couldn't create cache folders",
	"Cannot create cache folders",
	"No resources for this platform found",
	"does not exist or cannot be accessed",
	"failed! Please check path",
	"cannot execute binary file",
	"error while loading shared libraries",
	"Premature end of Skyscraper run",
}

local function gameEvent(n, total, rest)
	local ev = { kind = "game", n = tonumber(n), total = tonumber(total) }
	local title = rest:match("Game '(.*)' found!")
	if title then
		ev.status, ev.title = "found", title
		return ev
	end
	title = rest:match("Game '(.*)' match %('.*too low")
	if title then
		ev.status, ev.title = "missing", title
		return ev
	end
	title = rest:match("Game '(.*)' not found")
	if title then
		ev.status, ev.title = "missing", title
		return ev
	end
	title = rest:match("Skipping game '(.*)' since")
	if title then
		ev.status, ev.title = "skipped", title
		return ev
	end
	ev.status, ev.title = "unknown", rest
	return ev
end

function parser.parse(rawLine)
	local line = util.trim(util.stripAnsi(rawLine))
	if line == "" then
		return nil
	end

	local n, total, found, missed = line:match("^#(%d+)/(%d+), %((%d+)/(%d+)%)$")
	if n then
		return {
			kind = "tally",
			n = tonumber(n),
			total = tonumber(total),
			found = tonumber(found),
			missed = tonumber(missed),
		}
	end
	local rest
	n, total, rest = line:match("^#(%d+)/(%d+)%s+(.*)$")
	if n then
		return gameEvent(n, total, rest)
	end

	local h, m, s = line:match("^Elapsed time%s*:%s*(%d+):(%d+):(%d+)")
	if h then
		return { kind = "elapsed", seconds = hms(h, m, s) }
	end
	h, m, s = line:match("^Est%. time left%s*:%s*(%d+):(%d+):(%d+)")
	if h then
		return { kind = "eta", seconds = hms(h, m, s) }
	end

	local threads = line:match("Setting threads to (%d+) as allowed")
	if threads then
		return { kind = "threads", threads = tonumber(threads), allowed = tonumber(threads) }
	end
	local allowed = line:match("User is allowed (%d+) thread")
	if allowed then
		local manual = line:match("manually to (%d+)")
		return { kind = "threads", allowed = tonumber(allowed), threads = tonumber(manual) }
	end
	-- before the thread count: this one ends in "Forcing 1 thread..."
	if line:find("invalid / empty ScreenScraper server response", 1, true) then
		return { kind = "busy", text = line }
	end
	threads = line:match("Forcing (%d+) thread")
	if threads then
		return {
			kind = "threads",
			threads = tonumber(threads),
			anonymous = line:find("anonymous", 1, true) ~= nil,
		}
	end
	local files
	files, threads = line:match("Starting scraping run on (%d+) files using (%d+) thread")
	if files then
		return { kind = "start", files = tonumber(files), threads = tonumber(threads) }
	end
	local user = line:match("Fetching limits for user '(.*)', just a sec")
	if user then
		return { kind = "account", user = user }
	end
	if line:find("ScreenScraper login error", 1, true) then
		return { kind = "login_error", text = line }
	end
	if line:find("too busy to handle requests from unregistered", 1, true) then
		return { kind = "busy", text = line }
	end
	if line:find("No entries to scrape", 1, true) then
		return { kind = "nothing" }
	end
	for _, stop in ipairs(STOPS) do
		if line:find(stop[1], 1, true) then
			return { kind = "stop", reason = stop[2], text = line }
		end
	end
	local count = line:match("^Successfully processed games: (%d+)")
	if count then
		return { kind = "summary", found = tonumber(count) }
	end
	count = line:match("^Skipped games: (%d+)")
	if count then
		return { kind = "summary", skipped = tonumber(count) }
	end
	-- a listed ROM is gone, or its name does not survive the include list: the run ends here
	local gone = line:match("^Filename: '(.*)' requested either on command line")
	if gone then
		return { kind = "error", text = "Game file not found: " .. gone .. ". Rescan games and try again." }
	end
	for _, pattern in ipairs(ERRORS) do
		if line:find(pattern, 1, true) then
			return { kind = "error", text = line }
		end
	end
	return { kind = "log", text = line }
end

--- Runner control lines ("@@PID 123", "@@EXIT 0") that frame every Skyscraper run
function parser.control(rawLine)
	local pid = rawLine:match("^@@PID (%d+)")
	if pid then
		return "pid", tonumber(pid)
	end
	local code = rawLine:match("^@@EXIT (%-?%d+)")
	if code then
		return "exit", tonumber(code)
	end
	return nil
end

return parser
