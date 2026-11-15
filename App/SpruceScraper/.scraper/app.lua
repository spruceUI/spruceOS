--- Application state, screen switching and worker events
---
--- Test hooks (any run): SCRAPER_AUTORUN=1 scrapes the selected systems after the first scan
--- and quits, printing "AUTORUN DONE ..."; SCRAPER_AUTOSTOP=<n> presses Stop when the n-th game
--- of a scrape has been found; SCRAPER_SCREEN=<name> opens that screen at start;
--- SCRAPER_SCREENSHOT=/abs/file.png saves the window after SCRAPER_SCREENSHOT_DELAY seconds
--- (default 1.5) and quits.
local env = require("env")
local input = require("input")
local job = require("scraper.job")
local settings = require("settings")
local modal = require("ui.modal")
local version = require("version")

local app = {
	paths = nil,
	library = nil, -- system summaries from the last scan; nil until it finishes
	scanning = false,
	scanLabel = nil,
	runner = nil, -- "pty" (live progress) or "pipe"
	skyscraper = nil, -- { version = "3.21.1" } or { missing = true } or { failed = true }
	account = nil, -- last account check
	checkingAccount = false,
	notice = nil, -- one message for the home screen
	scraping = false,
}

local screens = {}
local current, currentName
local autorun = os.getenv("SCRAPER_AUTORUN") == "1"
local autorunStarted = false
local autostop = tonumber(os.getenv("SCRAPER_AUTOSTOP") or "")
local foundGames = 0
local screenshotPath = os.getenv("SCRAPER_SCREENSHOT")
local screenshotDelay = tonumber(os.getenv("SCRAPER_SCREENSHOT_DELAY") or "") or 1.5
local clock = 0

function app.register(name, screen)
	screens[name] = screen
end

function app.switch(name, params)
	local screen = screens[name]
	if not screen then
		error("no screen " .. tostring(name))
	end
	current, currentName = screen, name
	if screen.enter then
		screen.enter(params or {})
	end
end

function app.currentName()
	return currentName
end

--- The app's data folder as the user finds it on the card: "Saves/SpruceScraper/logs"
function app.dataPath(sub)
	local base = (app.paths.userdata:gsub("^/mnt/SDCARD/", ""))
	return sub and (base .. "/" .. sub) or base
end

function app.log(msg)
	print(os.date("%H:%M:%S") .. " " .. msg)
	io.stdout:flush()
end

function app.load()
	app.paths = env.load()
	os.execute("mkdir -p '" .. app.paths.userdata:gsub("'", "'\\''") .. "'")
	settings.load(app.paths.userdata .. "/settings.json")
	local imported = settings.importAccountFile(app.paths.accountFile)
	if imported then
		app.notice = "Imported the ScreenScraper account \"" .. imported .. "\" from screenscraper.txt"
	end
	app.log(string.format("Spruce Scraper %s on %s, roms %s", version.string(), app.paths.platform,
		table.concat(app.paths.romRoots, ", ")))
	job.start(app.paths)
	app.rescan()
	for _, name in ipairs({ "home", "systems", "account", "keyboard", "scrape", "summary", "about" }) do
		app.register(name, require("screens." .. name))
	end
	app.switch(os.getenv("SCRAPER_SCREEN") or "home")
end

function app.rescan()
	app.scanning = true
	app.scanLabel = nil
	job.send({ cmd = "scan" })
end

--- Systems the next scrape covers: selected, on ScreenScraper, and with something to do
function app.selectedSystems()
	local names, games = {}, 0
	local overwrite = settings.get("overwrite")
	for _, sys in ipairs(app.library or {}) do
		if sys.platform and settings.isSelected(sys.name) then
			local todo = overwrite and sys.total or sys.missing
			if todo > 0 then
				names[#names + 1] = sys.name
				games = games + todo
			end
		end
	end
	return names, games
end

function app.startScrape()
	local names = app.selectedSystems()
	if #names == 0 then
		return false
	end
	app.scraping = true
	foundGames = 0
	job.send({ cmd = "scrape", systems = names, settings = settings.values, overwrite = settings.get("overwrite") })
	app.switch("scrape")
	return true
end

function app.checkAccount()
	app.checkingAccount = true
	app.account = nil
	job.send({ cmd = "account", settings = settings.values })
end

local function handleEvent(ev)
	if ev.kind == "scan_progress" then
		app.scanLabel = ev.label
	elseif ev.kind == "scan_done" then
		app.library = ev.systems
		app.scanning = false
		if autorun and not autorunStarted then
			autorunStarted = true
			if not app.startScrape() then
				app.log("AUTORUN DONE nothing to scrape")
				love.event.quit(0)
			end
		end
	elseif ev.kind == "runner" then
		app.runner = ev.name
		app.log("runner: " .. ev.name .. (ev.python and (" (" .. ev.python .. ")") or ""))
	elseif ev.kind == "skyscraper" then
		app.skyscraper = ev
		app.log("skyscraper: " .. (ev.version or (ev.missing and "missing" or "failed to start")))
		if ev.output then
			app.log("skyscraper output: " .. ev.output)
		end
	elseif ev.kind == "account_result" then
		app.account = ev
		app.checkingAccount = false
		app.log(string.format("account check: ok=%s allowed=%s login_error=%s", tostring(ev.ok),
			tostring(ev.allowed), tostring(ev.loginError)))
	elseif ev.kind == "job_done" then
		app.scraping = false
		local problems = 0
		for _, r in ipairs(ev.results or {}) do
			if r.problem then
				problems = problems + 1
			end
		end
		app.log(string.format("job done: saved %d of %d, not found %d, stop %s, cancelled %s, problems %d", ev.saved or 0,
			ev.todo or 0, ev.notFound or 0, tostring(ev.stopReason), tostring(ev.cancelled), problems))
		if autorun then
			app.log(string.format("AUTORUN DONE saved=%d todo=%d notfound=%d stop=%s problems=%d cancelled=%s",
				ev.saved or 0, ev.todo or 0, ev.notFound or 0, tostring(ev.stopReason), problems, tostring(ev.cancelled)))
			love.event.quit((ev.stopReason or problems > 0) and 1 or 0)
		end
	elseif ev.kind == "worker_error" then
		app.log("worker error: " .. tostring(ev.text))
		app.notice = "Something went wrong: " .. tostring(ev.text)
	elseif ev.kind == "game" then
		if ev.status == "found" then
			foundGames = foundGames + 1
			if autostop and foundGames == autostop then
				app.log("AUTOSTOP after " .. tostring(ev.title))
				job.cancel()
			end
		end
	elseif ev.kind == "problem" then
		app.log("problem: " .. tostring(ev.label) .. ": " .. tostring(ev.text))
	elseif ev.kind == "error" or ev.kind == "stop" or ev.kind == "login_error" or ev.kind == "preflight" then
		app.log(ev.kind .. ": " .. tostring(ev.text))
	end
end

function app.update(dt)
	clock = clock + dt
	local err = job.error()
	if err then
		error("worker thread: " .. err)
	end
	for _, ev in ipairs(job.poll()) do
		handleEvent(ev)
		if current and current.onEvent then
			current.onEvent(ev)
		end
	end
	input.update(dt)
	for _, action in ipairs(input.pressed()) do
		if modal.isOpen() then
			modal.handle(action)
		elseif current and current.handle then
			current.handle(action)
		end
	end
	if current and current.update then
		current.update(dt)
	end
	if screenshotPath and clock >= screenshotDelay then
		local path = screenshotPath
		screenshotPath = nil
		love.graphics.captureScreenshot(function(imageData)
			local f = io.open(path, "wb")
			if f then
				f:write(imageData:encode("png"):getString())
				f:close()
			end
			app.log("SCREENSHOT " .. path)
			love.event.quit(0)
		end)
	end
end

function app.draw()
	if current and current.draw then
		current.draw()
	end
	modal.draw()
end

function app.quit()
	settings.save()
	job.shutdown()
end

return app
