--- spruce system detection, following how PyUI builds its game system list
---
--- PyUI (games/utils/device_specific/miyoo_trim_game_system_utils.py) reads every
--- Emu/<SYS>/config.json and looks for ROMs in <root>/<SYS> plus each alternativeFolderNames
--- entry, for root in /mnt/SDCARD/Roms and /media/sdcard1/Roms. A file is a ROM when its last
--- extension is in the config's extlist; subfolders are scanned unless scanSubfolders is false.
local platforms = require("scraper.platforms")
local romscan = require("scraper.romscan")

local systems = {}

-- Folder names are matched against each root's listing instead of stat'ed: FAT is
-- case-insensitive, so "Roms/sfc" would stat as "Roms/SFC" and one folder be scanned twice.
local function listRoots(fs, roots)
	local listings = {}
	for _, root in ipairs(roots) do
		local entries = fs.list(root)
		if entries then
			local dirs = {}
			for _, e in ipairs(entries) do
				if e.isDir then
					dirs[e.name] = true
				end
			end
			listings[#listings + 1] = { path = root, dirs = dirs }
		end
	end
	return listings
end

local function folderPaths(listings, name, alternatives)
	local candidates = { name }
	if type(alternatives) == "table" then
		for _, alt in ipairs(alternatives) do
			if type(alt) == "string" and alt ~= "" then
				candidates[#candidates + 1] = alt
			end
		end
	end
	local paths, seen = {}, {}
	for _, root in ipairs(listings) do
		for _, folder in ipairs(candidates) do
			local path = root.path .. "/" .. folder
			if root.dirs[folder] and not seen[path] then
				seen[path] = true
				paths[#paths + 1] = path
			end
		end
	end
	return paths
end

local function readConfig(fs, decodeJson, emuDir, name)
	local raw = fs.read(emuDir .. "/" .. name .. "/config.json")
	if not raw then
		return nil
	end
	local ok, cfg = pcall(decodeJson, raw)
	if ok and type(cfg) == "table" then
		return cfg
	end
	return nil
end

--- Build one system record from its config, or nil when it has no ROMs
local function buildSystem(fs, name, cfg, listings, claimed, onProgress)
	local extlist = type(cfg.extlist) == "string" and cfg.extlist or ""
	local extSet = romscan.parseExtlist(extlist)
	if next(extSet) == nil then
		return nil
	end
	local label = type(cfg.label) == "string" and cfg.label ~= "" and cfg.label or name
	local sys = {
		name = name,
		label = label,
		platform = platforms.forSystem(name),
		extlist = extlist,
		folders = {},
		total = 0,
		missing = 0,
	}
	local scanSubfolders = cfg.scanSubfolders ~= false
	for _, path in ipairs(folderPaths(listings, name, cfg.alternativeFolderNames)) do
		-- two configs may claim one folder; scrape it once, for the first system that claims it
		if not claimed[path] then
			claimed[path] = name
			if onProgress then
				onProgress(label)
			end
			local cache = {}
			local roms = romscan.scanFolder(fs, path, extSet, scanSubfolders)
			for _, rom in ipairs(roms) do
				rom.imgBase = romscan.imageBaseName(rom.name, extSet)
				rom.hasArt = romscan.hasArt(fs, cache, path, rom.rel, rom.imgBase)
				if not rom.hasArt then
					sys.missing = sys.missing + 1
				end
			end
			if #roms > 0 then
				sys.total = sys.total + #roms
				sys.folders[#sys.folders + 1] = { path = path, roms = roms }
			end
		end
	end
	if sys.total == 0 then
		return nil
	end
	return sys
end

--- Every system with at least one ROM, sorted by label.
--- opts: fs, decodeJson, emuDir, romRoots (array), onProgress(label) (optional)
function systems.detect(opts)
	local fs = opts.fs
	local listings = listRoots(fs, opts.romRoots)
	local entries = fs.list(opts.emuDir) or {}
	table.sort(entries, function(a, b)
		return a.name < b.name
	end)
	local result, claimed = {}, {}
	for _, e in ipairs(entries) do
		if e.isDir and e.name:sub(1, 1) ~= "." then
			local cfg = readConfig(fs, opts.decodeJson, opts.emuDir, e.name)
			if cfg then
				local sys = buildSystem(fs, e.name, cfg, listings, claimed, opts.onProgress)
				if sys then
					result[#result + 1] = sys
				end
			end
		end
	end
	table.sort(result, function(a, b)
		local la, lb = a.label:lower(), b.label:lower()
		if la == lb then
			return a.name < b.name
		end
		return la < lb
	end)
	return result
end

--- What the UI needs, without the ROM lists (they stay in the worker)
function systems.summarize(list)
	local out = {}
	for i, sys in ipairs(list) do
		out[i] = {
			name = sys.name,
			label = sys.label,
			platform = sys.platform,
			total = sys.total,
			missing = sys.missing,
			folders = #sys.folders,
		}
	end
	return out
end

return systems
