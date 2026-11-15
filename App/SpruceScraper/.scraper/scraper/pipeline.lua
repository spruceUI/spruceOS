--- One scrape job: for every selected system and ROM folder, gather -> render -> install
---
--- Pure Lua. The worker thread supplies the side effects, so tests can drive it with a fake
--- filesystem and a fake Skyscraper:
---   ctx.fs           list/isDir/isFile/read/write/mkdirs/move/remove/removeTree (scraper/fsys.lua)
---   ctx.spawn(argv, onLine, kind) -> exit code, or nil when the program could not be started;
---                    kind is "gather" (downloads) or "render" (makes the images)
---   ctx.stopCurrent() asks the running Skyscraper to finish nicely (SIGINT)
---   ctx.isCancelled() true once the user pressed Stop
---   ctx.emit(event)  progress for the UI
---   ctx.paths        bin, config, work, cache, replaced, pyuiTrigger
--- job: systems (full records from scraper/systems.lua), overwrite, threads, artwork, outputType
local parser = require("scraper.parser")
local romscan = require("scraper.romscan")
local skyconfig = require("scraper.skyconfig")
local util = require("scraper.util")

local pipeline = {}

local VARIANT_DIRS = { "Imgs", "Imgs_large", "Imgs_med", "Imgs_small" }

-- Bytes of file names one run may carry on its command line: popen hands the whole command to
-- "sh -c" as a single argument, which Linux caps at 128 KB
local ARG_BUDGET = 48 * 1024

-- Lower-cased name -> name on the card for a folder's files, listed once per ROM folder
local function namesOf(fs, listings, dir)
	local names = listings[dir]
	if not names then
		names = {}
		for _, e in ipairs(fs.list(dir) or {}) do
			if not e.isDir then
				names[e.name:lower()] = e.name
			end
		end
		listings[dir] = names
	end
	return names
end

-- Move a ROM's existing images (and PyUI's resized copies) aside before writing a new one: PyUI
-- prefers a .qoi over a .png and never re-optimizes an image whose .qoi exists. Any spelling
-- counts: FAT keeps the old name when a file is written over, and PyUI matches names exactly.
local function backupExisting(ctx, listings, folderPath, rom, backupRoot)
	local fs = ctx.fs
	local moved = 0
	for _, variant in ipairs(VARIANT_DIRS) do
		local dir = util.joinPath(folderPath, variant, rom.rel)
		local names = namesOf(fs, listings, dir)
		for _, ext in ipairs(romscan.IMAGE_EXTS) do
			local key = (rom.imgBase .. ext):lower()
			local name = names[key]
			if name then
				local dest = util.joinPath(backupRoot, util.basename(folderPath), variant, rom.rel, name)
				fs.mkdirs(util.dirname(dest))
				if fs.move(dir .. "/" .. name, dest) then
					moved = moved + 1
					names[key] = nil
				end
			end
		end
	end
	return moved
end

local function folderTodo(job, folder)
	local todo = {}
	for _, rom in ipairs(folder.roms) do
		if job.overwrite or not rom.hasArt then
			todo[#todo + 1] = rom
		end
	end
	return todo
end

--- Number of ROMs a job will look up
function pipeline.countTodo(job)
	local n = 0
	for _, sys in ipairs(job.systems) do
		for _, folder in ipairs(sys.folders) do
			n = n + #folderTodo(job, folder)
		end
	end
	return n
end

--- Split a folder's ROMs into Skyscraper runs: { roms, listed, args }. Skyscraper names its
--- images by file name alone, so two ROMs of one name (in two subfolders) cannot share a run.
--- Paths its include list would mangle go on the command line, which has a size limit.
function pipeline.batches(todo)
	local out = {}
	for _, rom in ipairs(todo) do
		local key = util.completeBaseName(rom.name):lower()
		local cost = skyconfig.listable(rom.path) and 0 or (#util.shellQuote(rom.path) + 1)
		local i = 1
		while out[i] and (out[i].names[key] or out[i].argBytes + cost > ARG_BUDGET) do
			i = i + 1
		end
		local batch = out[i]
		if not batch then
			batch = { roms = {}, listed = {}, args = {}, names = {}, argBytes = 0 }
			out[i] = batch
		end
		batch.roms[#batch.roms + 1] = rom
		batch.names[key] = true
		if cost == 0 then
			batch.listed[#batch.listed + 1] = rom.path
		else
			batch.args[#batch.args + 1] = rom.path
			batch.argBytes = batch.argBytes + cost
		end
	end
	return out
end

-- A run that was cut off can leave half an image behind
local function completePng(data)
	return data ~= nil and data:sub(1, 8) == "\137PNG\r\n\26\n" and data:sub(-8) == "IEND\174B`\130"
end

-- Skyscraper ended a run badly and no stop reason explains it: say so for this system, with
-- its own error line when it printed one, else its last line and exit code
local function fail(ctx, sys, sysStats, said, lastLine, code)
	local text = said
	if not text then
		text = "Skyscraper stopped (code " .. tostring(code) .. ")" .. (lastLine and (": " .. lastLine) or "")
	end
	sysStats.problem = sysStats.problem or text
	ctx.emit({ kind = "problem", system = sys.name, label = sys.label, text = text, unseen = said == nil })
	return false
end

-- nil: popen failed; 126/127: the shell or the loader could not run the program
local function notStarted(ctx, stats, code)
	if code == nil or code == 126 or code == 127 then
		stats.stopReason = "spawn"
		ctx.emit({ kind = "error", text = "Skyscraper could not be started" })
		return true
	end
	return false
end

--- Download, render and install one batch. True when nothing cut it short: a Stop that came
--- after every game was already in progress leaves the batch whole.
local function runBatch(ctx, job, sys, folder, batch, stats, sysStats, listings)
	local fs = ctx.fs
	local work = ctx.paths.work
	local media = work .. "/media"
	local gamelist = work .. "/gamelist"
	local include
	fs.mkdirs(work)
	if #batch.listed > 0 then
		include = work .. "/include.txt"
		fs.write(include, table.concat(batch.listed, "\n") .. "\n")
	end
	local run = {
		bin = ctx.paths.bin,
		platform = sys.platform,
		config = ctx.paths.config,
		input = folder.path,
		include = include,
		files = batch.args,
		addext = romscan.addextArgument(sys.extlist),
		threads = job.threads,
		artwork = job.artwork,
		gamelist = gamelist,
		media = media,
	}

	ctx.emit({ kind = "phase", phase = "gather", system = sys.name, folder = folder.path, todo = #batch.roms })
	local inCache, said, lastLine = 0, nil, nil
	local missing, saved = 0, 0
	local function whole()
		return saved + missing >= #batch.roms or not (stats.stopReason or ctx.isCancelled())
	end
	local code = ctx.spawn(skyconfig.gatherArgs(run), function(line)
		local ev = parser.parse(line)
		if not ev then
			return
		end
		ev.system = sys.name
		if ev.kind == "game" then
			if ev.status == "found" then
				sysStats.found = sysStats.found + 1
				inCache = inCache + 1
			elseif ev.status == "skipped" then
				-- downloaded by an earlier run that was stopped before it made the image
				inCache = inCache + 1
			elseif ev.status == "missing" then
				sysStats.notFound = sysStats.notFound + 1
				stats.notFound = stats.notFound + 1
				missing = missing + 1
			end
			stats.looked = stats.looked + 1
		elseif ev.kind == "login_error" then
			-- Skyscraper would carry on anonymously with one thread; stop and say so instead
			stats.stopReason = "login"
			ctx.stopCurrent()
		elseif ev.kind == "stop" then
			stats.stopReason = stats.stopReason or ev.reason
		elseif ev.kind == "error" then
			said = said or ev.text
		elseif ev.kind == "log" then
			lastLine = ev.text
		end
		ctx.emit(ev)
	end, "gather")
	if notStarted(ctx, stats, code) or stats.stopReason == "login" then
		return false
	end
	if code ~= 0 and not stats.stopReason and not ctx.isCancelled() then
		return fail(ctx, sys, sysStats, said, lastLine, code)
	end
	if inCache == 0 then
		-- nothing to make images from (a game list run over an empty cache ends in an error)
		return whole()
	end

	-- Render even after Stop or a quota stop: what was downloaded so far is in the cache
	ctx.emit({ kind = "phase", phase = "render", system = sys.name })
	fs.removeTree(media)
	fs.mkdirs(media)
	fs.mkdirs(gamelist)
	said, lastLine = nil, nil
	code = ctx.spawn(skyconfig.generateArgs(run), function(line)
		local ev = parser.parse(line)
		if not ev then
			return
		end
		if ev.kind == "error" or ev.kind == "stop" then
			ev.system = sys.name
			if ev.kind == "error" then
				said = said or ev.text
			else
				stats.stopReason = stats.stopReason or ev.reason
			end
			ctx.emit(ev)
		elseif ev.kind == "log" then
			lastLine = ev.text
		end
	end, "render")
	if notStarted(ctx, stats, code) then
		return false
	end

	ctx.emit({ kind = "phase", phase = "install", system = sys.name })
	for _, rom in ipairs(batch.roms) do
		local src = romscan.skyscraperOutput(media, job.outputType, rom.name)
		if fs.isFile(src) and (code == 0 or completePng(fs.read(src))) then
			backupExisting(ctx, listings, folder.path, rom, ctx.paths.replaced .. "/" .. sys.name)
			local dst = romscan.targetPath(folder.path, rom.rel, rom.imgBase)
			fs.mkdirs(util.dirname(dst))
			local ok, err = fs.move(src, dst)
			if ok then
				rom.hasArt = true
				saved = saved + 1
				stats.saved = stats.saved + 1
				sysStats.saved = sysStats.saved + 1
				ctx.emit({ kind = "saved", system = sys.name, path = dst, title = rom.imgBase })
			else
				stats.failed = stats.failed + 1
				ctx.emit({ kind = "error", system = sys.name, text = "Could not write " .. dst .. ": " .. tostring(err) })
			end
		end
	end
	if code ~= 0 and not stats.stopReason and not ctx.isCancelled() then
		return fail(ctx, sys, sysStats, said, lastLine, code)
	end
	return whole()
end

local function runFolder(ctx, job, sys, folder, todo, stats, sysStats)
	local fs = ctx.fs
	local cache = ctx.paths.cache and (ctx.paths.cache .. "/" .. sys.platform)
	-- Replace: an earlier run's download must not stand in for a new one
	if job.overwrite and cache then
		fs.removeTree(cache)
	end
	local listings = {}
	local complete = true
	for _, batch in ipairs(pipeline.batches(todo)) do
		if ctx.isCancelled() or stats.stopReason then
			complete = false
			break
		end
		if not runBatch(ctx, job, sys, folder, batch, stats, sysStats, listings) then
			complete = false
		end
	end
	fs.removeTree(ctx.paths.work .. "/media")
	fs.removeTree(ctx.paths.work .. "/gamelist")
	fs.remove(ctx.paths.work .. "/include.txt")
	-- Every image is on the card, so the downloads are not needed again. A run that was cut
	-- short keeps them: the next one picks them up without asking ScreenScraper again.
	if complete and cache then
		fs.removeTree(cache)
	end
end

function pipeline.run(ctx, job)
	-- systems ScreenScraper has no platform for cannot be looked up
	local scrapable = {}
	for _, sys in ipairs(job.systems) do
		if sys.platform then
			scrapable[#scrapable + 1] = sys
		end
	end
	job.systems = scrapable
	local stats = { saved = 0, notFound = 0, failed = 0, looked = 0, todo = pipeline.countTodo(job), results = {} }
	ctx.emit({ kind = "job_start", systems = #job.systems, todo = stats.todo })
	for index, sys in ipairs(job.systems) do
		if ctx.isCancelled() or stats.stopReason then
			break
		end
		local sysTodo = 0
		for _, folder in ipairs(sys.folders) do
			sysTodo = sysTodo + #folderTodo(job, folder)
		end
		local sysStats = { name = sys.name, label = sys.label, todo = sysTodo, found = 0, notFound = 0, saved = 0 }
		stats.results[#stats.results + 1] = sysStats
		ctx.emit({
			kind = "system_start",
			index = index,
			count = #job.systems,
			name = sys.name,
			label = sys.label,
			todo = sysTodo,
		})
		for _, folder in ipairs(sys.folders) do
			if ctx.isCancelled() or stats.stopReason then
				break
			end
			local todo = folderTodo(job, folder)
			if #todo > 0 then
				runFolder(ctx, job, sys, folder, todo, stats, sysStats)
			end
		end
		sys.missing = 0
		for _, folder in ipairs(sys.folders) do
			for _, rom in ipairs(folder.roms) do
				if not rom.hasArt then
					sys.missing = sys.missing + 1
				end
			end
		end
		ctx.emit({
			kind = "system_done",
			name = sys.name,
			label = sys.label,
			todo = sysStats.todo,
			saved = sysStats.saved,
			notFound = sysStats.notFound,
			missing = sys.missing,
			problem = sysStats.problem,
		})
	end
	-- PyUI converts the new PNGs to QOI (and makes its small/medium copies) on its next start
	if stats.saved > 0 and ctx.paths.pyuiTrigger then
		ctx.fs.write(ctx.paths.pyuiTrigger, "")
	end
	ctx.emit({
		kind = "job_done",
		saved = stats.saved,
		notFound = stats.notFound,
		failed = stats.failed,
		todo = stats.todo,
		looked = stats.looked,
		cancelled = ctx.isCancelled() and true or false,
		stopReason = stats.stopReason,
		results = stats.results,
	})
	return stats
end

return pipeline
