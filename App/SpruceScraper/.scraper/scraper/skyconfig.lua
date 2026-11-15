--- Skyscraper config.ini, artwork templates and command lines
---
--- Each folder is two Skyscraper runs, as in Scrappy: a resource gathering run
--- (-s screenscraper) that downloads into Skyscraper's cache, then a game list run (no -s) that
--- renders the artwork template from the cache into a work folder. Both name the same files (an
--- --includefrom list plus command-line names), so only the ROMs that need art are touched.
local regions = require("scraper.regions")

local skyconfig = {}

--- A double-quoted INI string (Skyscraper's INI format: backslash escapes the quote)
function skyconfig.iniString(v)
	return '"' .. tostring(v):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

--- Resource types a template draws from, and the type of image it writes
function skyconfig.templateInfo(xml)
	local info = { resources = {}, output = nil }
	for attrs in xml:gmatch("<output%s([^>]*)>") do
		local outType = attrs:match('type="([^"]+)"')
		if outType and not info.output then
			info.output = outType
		end
		local res = attrs:match('resource="([^"]+)"') or outType
		if res then
			info.resources[res] = true
		end
	end
	for attrs in xml:gmatch("<layer%s([^>]*)>") do
		local res = attrs:match('resource="([^"]+)"')
		if res then
			info.resources[res] = true
		end
	end
	return info
end

local CACHE_KEYS = {
	cover = "cacheCovers",
	screenshot = "cacheScreenshots",
	wheel = "cacheWheels",
	marquee = "cacheMarquees",
	texture = "cacheTextures",
}

--- config.ini text. opts: username, password, regionChoice, spruceRegion, resources (set)
function skyconfig.configIni(opts)
	local lines = { "; written by Spruce Scraper for each run; edits are overwritten", "[main]" }
	local function put(key, value)
		lines[#lines + 1] = key .. "=" .. skyconfig.iniString(value)
	end
	put("frontend", "emulationstation")
	put("unattend", "true")
	put("hints", "false")
	put("verbosity", "1")
	put("subdirs", "true")
	put("gameListBackup", "false")
	put("videos", "false")
	put("manuals", "false")
	put("backcovers", "false")
	put("fanarts", "false")
	local resources = opts.resources or { cover = true }
	for _, res in ipairs({ "cover", "screenshot", "wheel", "marquee", "texture" }) do
		put(CACHE_KEYS[res], resources[res] and "true" or "false")
	end
	local r = regions.settings(opts.regionChoice, opts.spruceRegion)
	if r.region then
		put("region", r.region)
	end
	put("regionPrios", r.regionPrios)
	put("regionFromFilename", r.regionFromFilename)
	lines[#lines + 1] = ""
	lines[#lines + 1] = "[screenscraper]"
	if skyconfig.hasCredentials(opts) then
		put("userCreds", opts.username .. ":" .. opts.password)
	end
	return table.concat(lines, "\n") .. "\n"
end

function skyconfig.hasCredentials(opts)
	return type(opts.username) == "string" and opts.username ~= ""
		and type(opts.password) == "string" and opts.password ~= ""
end

--- Characters Skyscraper before 3.21 did not percent-encode in its request URL, so a password
--- holding one fails to log in with the interim 3.17 binary (Gemba/skyscraper#270)
function skyconfig.passwordNeedsNewSkyscraper(password)
	return type(password) == "string" and password:find("[^%w%-%._~]") ~= nil
end

--- True when a path survives Skyscraper's --includefrom reader. It passes every line through
--- QByteArray::simplified(), so a name with two spaces in a row, a tab or a line break comes out
--- changed, is "not found" and ends the whole run. Such paths go on the command line instead.
function skyconfig.listable(path)
	return not (path:find("[\t\n\v\f\r]") or path:find("  ", 1, true) or path:find("^ ") or path:find(" $"))
end

-- The files a run covers: include (a file of paths, one per line) and files (more paths, given
-- as arguments after every option; see listable)
local function withInclude(argv, p)
	if p.include then
		argv[#argv + 1] = "--includefrom"
		argv[#argv + 1] = p.include
	end
	return argv
end

local function withAddext(argv, p)
	if p.addext and p.addext ~= "" then
		argv[#argv + 1] = "--addext"
		argv[#argv + 1] = p.addext
	end
	return argv
end

local function withFiles(argv, p)
	for _, path in ipairs(p.files or {}) do
		argv[#argv + 1] = path
	end
	return argv
end

--- argv for the resource gathering run.
--- p: bin, platform, config, input, include, files, addext, threads
function skyconfig.gatherArgs(p)
	local argv = withInclude({ p.bin, "-p", p.platform, "-s", "screenscraper", "-c", p.config, "-i", p.input }, p)
	argv[#argv + 1] = "--flags"
	argv[#argv + 1] = "unattend,onlymissing"
	withAddext(argv, p)
	-- Skyscraper ignores -t above the CPU count; without -t it uses the account's allowance
	if p.threads and p.threads > 0 then
		argv[#argv + 1] = "-t"
		argv[#argv + 1] = tostring(p.threads)
	end
	return withFiles(argv, p)
end

--- argv for the game list run that renders the template into media.
--- p: bin, platform, config, input, include, files, addext, artwork, gamelist, media
function skyconfig.generateArgs(p)
	local argv = withInclude({ p.bin, "-p", p.platform, "-c", p.config, "-i", p.input }, p)
	for _, a in ipairs({ "-a", p.artwork, "-g", p.gamelist, "-o", p.media, "-f", "emulationstation", "--flags", "unattend" }) do
		argv[#argv + 1] = a
	end
	return withFiles(withAddext(argv, p), p)
end

--- argv for an account check: a gathering run over an empty folder still fetches the user's limits
function skyconfig.accountCheckArgs(p)
	return { p.bin, "-p", "snes", "-s", "screenscraper", "-c", p.config, "-i", p.input, "--flags", "unattend" }
end

return skyconfig
