--- Worker thread: library scans, Skyscraper runs and account checks, off the UI thread
---
--- Commands arrive on "scraper_in", events leave on "scraper_out"; "scraper_cancel" carries
--- Stop. The full ROM lists stay here, the UI only receives counts. Started by scraper/job.lua
--- with the paths table from env.lua.
local paths = ...

local json = require("lib.json")
local fsys = require("scraper.fsys")
local parser = require("scraper.parser")
local pipeline = require("scraper.pipeline")
local skyconfig = require("scraper.skyconfig")
local skyenv = require("scraper.skyenv")
local spawn = require("scraper.spawn")
local systems = require("scraper.systems")
local util = require("scraper.util")

local inbox = love.thread.getChannel("scraper_in")
local outbox = love.thread.getChannel("scraper_out")
local cancelChannel = love.thread.getChannel("scraper_cancel")

local library = {}
local currentPid = nil
local cancelled = false
local python = nil
local skyscraperVersion = nil

local home = paths.userdata .. "/skyscraper"
local skyDot = home .. "/.skyscraper"
local configPath = skyDot .. "/config.ini"
local workDir = paths.userdata .. "/work"

fsys.setGuard(paths.userdata)

local function emit(ev)
	outbox:push(ev)
end

local function isCancelled()
	if cancelChannel:pop() then
		cancelled = true
	end
	return cancelled
end

-- kind "render" is the run that turns downloads into images: Stop leaves it to finish, or what
-- was downloaded so far would not be saved. Every other run ends on Stop.
local function run(argv, onLine, kind)
	local stoppable = kind ~= "render"
	return spawn.run(argv, {
		env = skyenv.build(paths, home, fsys),
		cwd = home,
		python = python,
		ptyrun = paths.source .. "/tools/ptyrun.py",
		onPid = function(pid)
			currentPid = pid
			emit({ kind = "pid", pid = pid, stoppable = stoppable })
			-- Stop pressed before this run had a pid: honour it now
			if pid and cancelled and stoppable then
				spawn.interrupt(pid)
			end
		end,
		onLine = function(line)
			isCancelled()
			onLine(line)
		end,
	})
end

-- Skyscraper reads peas.json and platforms_idmap.csv from ~/.skyscraper; copy the ones
-- matching the bundled binary whenever the bundle changes
local function prepareHome()
	fsys.mkdirs(skyDot)
	fsys.mkdirs(workDir)
	local stamp = fsys.read(paths.skyscraper .. "/VERSION") or "unknown"
	if fsys.read(skyDot .. "/.spruce-scraper-data") ~= stamp then
		for _, name in ipairs({ "peas.json", "platforms_idmap.csv" }) do
			local data = fsys.read(paths.skyscraper .. "/data/" .. name)
			if data then
				fsys.write(skyDot .. "/" .. name, data)
			end
		end
		fsys.write(skyDot .. "/.spruce-scraper-data", stamp)
	end
end

local function probeTools()
	if spawn.pythonWorks(paths.python) then
		python = paths.python
	end
	emit({ kind = "runner", name = python and "pty" or "pipe", python = python })
	local bin = paths.skyscraper .. "/Skyscraper"
	if not fsys.isFile(bin) then
		emit({ kind = "skyscraper", missing = true })
		return
	end
	local lines = {}
	run({ bin, "--version" }, function(line)
		lines[#lines + 1] = util.stripAnsi(line)
	end)
	local text = table.concat(lines, "\n")
	skyscraperVersion = text:match("(%d+%.%d+%.%d+)")
	emit({
		kind = "skyscraper",
		version = skyscraperVersion,
		failed = skyscraperVersion == nil,
		output = skyscraperVersion == nil and text:sub(1, 400) or nil,
	})
end

-- Skyscraper reports an unreachable ScreenScraper, a clock too wrong for HTTPS or a certificate
-- it cannot verify as every game "not found"; name the cause before starting instead
-- (tools/netcheck.py). Without python the network check is skipped.
local function preflight()
	if not paths.preflight then
		return nil
	end
	if (tonumber(os.date("%Y")) or 0) < 2025 then
		return "clock"
	end
	if python then
		local ca = paths.caFile and fsys.isFile(paths.caFile) and paths.caFile or ""
		local p = io.popen(util.shellJoin({ python, paths.source .. "/tools/netcheck.py", ca }) .. " 2>/dev/null", "r")
		local answer = p and p:read("*l") or ""
		if p then
			p:close()
		end
		emit({ kind = "preflight", text = answer })
		local word = answer:match("^(%a+)")
		if word == "offline" or word == "clock" or word == "certificate" then
			return word
		end
	end
	return nil
end

local PREFLIGHT_MESSAGES = {
	clock = "The clock is wrong, so secure connections fail: set the time",
	offline = "No internet connection: connect to Wi-Fi first",
	certificate = "The secure connection to ScreenScraper could not be verified",
}

local function scan()
	emit({ kind = "scan_start" })
	library = systems.detect({
		fs = fsys,
		decodeJson = json.decode,
		emuDir = paths.emu,
		romRoots = paths.romRoots,
		onProgress = function(label)
			emit({ kind = "scan_progress", label = label })
		end,
	})
	emit({ kind = "scan_done", systems = systems.summarize(library) })
end

local function templateFor(name)
	local file = paths.source .. "/templates/" .. name .. ".xml"
	local xml = fsys.read(file)
	if not xml then
		file = paths.source .. "/templates/boxart.xml"
		xml = fsys.read(file) or ""
	end
	return file, skyconfig.templateInfo(xml)
end

local function writeConfig(settings, resources)
	prepareHome()
	return fsys.write(configPath, skyconfig.configIni({
		username = settings.username,
		password = settings.password,
		regionChoice = settings.region,
		spruceRegion = paths.spruceRegion,
		resources = resources,
	}))
end

local function scrape(cmd)
	cancelled = false
	cancelChannel:clear()
	local bin = paths.skyscraper .. "/Skyscraper"
	local problem = not fsys.isFile(bin) and "missing" or preflight()
	if problem then
		emit({ kind = "job_done", saved = 0, todo = 0, notFound = 0, failed = 0, results = {}, stopReason = problem })
		return
	end
	local wanted = {}
	for _, name in ipairs(cmd.systems or {}) do
		wanted[name] = true
	end
	local selected = {}
	for _, sys in ipairs(library) do
		if wanted[sys.name] then
			selected[#selected + 1] = sys
		end
	end
	local artwork, info = templateFor(cmd.settings.template or "boxart")
	writeConfig(cmd.settings, info.resources)
	pipeline.run({
		fs = fsys,
		spawn = run,
		stopCurrent = function()
			spawn.interrupt(currentPid)
		end,
		isCancelled = isCancelled,
		emit = emit,
		paths = {
			bin = bin,
			config = configPath,
			work = workDir,
			cache = skyDot .. "/cache",
			replaced = paths.userdata .. "/replaced/" .. os.date("%Y%m%d-%H%M%S"),
			pyuiTrigger = paths.pyuiTrigger,
		},
	}, {
		systems = selected,
		overwrite = cmd.overwrite and true or false,
		threads = tonumber(cmd.settings.threads) or 0,
		artwork = artwork,
		outputType = info.output or "cover",
	})
	emit({ kind = "scan_done", systems = systems.summarize(library) })
end

-- A gathering run over an empty folder stops after ScreenScraper's user check
local function checkAccount(settings)
	local result = { kind = "account_result", user = settings.username }
	local bin = paths.skyscraper .. "/Skyscraper"
	if not fsys.isFile(bin) then
		result.message = "Skyscraper is missing from this build"
		emit(result)
		return
	end
	local problem = preflight()
	if problem then
		result.message = PREFLIGHT_MESSAGES[problem]
		emit(result)
		return
	end
	writeConfig(settings, { cover = true })
	local empty = workDir .. "/empty"
	fsys.removeTree(empty)
	fsys.mkdirs(empty)
	local code = run(skyconfig.accountCheckArgs({ bin = bin, config = configPath, input = empty }), function(line)
		local ev = parser.parse(line)
		if not ev then
			return
		end
		if ev.kind == "threads" then
			result.allowed = ev.allowed or result.allowed
			result.threads = ev.threads or result.threads
			result.anonymous = ev.anonymous
		elseif ev.kind == "login_error" then
			result.loginError = true
		elseif ev.kind == "busy" or ev.kind == "stop" or ev.kind == "error" then
			result.message = ev.text
		end
	end)
	result.exitCode = code
	result.ok = not result.loginError and result.allowed ~= nil
	emit(result)
end

prepareHome()
probeTools()
while true do
	local cmd = inbox:demand()
	if type(cmd) ~= "table" or cmd.cmd == "quit" then
		break
	end
	local ok, err = pcall(function()
		if cmd.cmd == "scan" then
			scan()
		elseif cmd.cmd == "scrape" then
			scrape(cmd)
		elseif cmd.cmd == "account" then
			checkAccount(cmd.settings)
		end
	end)
	if not ok then
		emit({ kind = "worker_error", text = tostring(err) })
		if cmd.cmd == "scrape" then
			emit({ kind = "job_done", saved = 0, todo = 0, notFound = 0, failed = 0, results = {}, stopReason = "error" })
		end
	end
end
