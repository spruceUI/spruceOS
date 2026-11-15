--- ROM discovery and box art state, using PyUI's own rules so the art lands where PyUI looks
---
--- PyUI (App/PyUI/main-ui/menus/games/utils/rom_select_options_builder.py) shows
--- Roms/<SYS>/Imgs/<subfolders>/<name>.qoi|png|jpg|... and falls back to Roms/<SYS>/Imgs/<name>.*,
--- where <name> is the file name with every trailing extension from the system's extlist removed
--- (RomFileNameUtils.get_rom_name_without_extensions). It converts PNGs to QOI itself on its next
--- start when App/PyUI/pyui_resize_boxart_trigger exists.
local util = require("scraper.util")

local romscan = {}

romscan.IMAGE_EXTS = { ".qoi", ".png", ".jpg", ".jpeg", ".webp", ".bmp" }
romscan.MAX_DEPTH = 8

--- PyUI's get_extlist: "zip|7z|SFC" -> { [".zip"] = true, [".7z"] = true, [".sfc"] = true }
function romscan.parseExtlist(extlist)
	local set = {}
	for ext in (extlist or ""):lower():gmatch("[^|]+") do
		set["." .. ext] = true
	end
	return set
end

--- Skyscraper's --addext argument for an extlist: "*.zip *.7z *.sfc"
function romscan.addextArgument(extlist)
	local out, seen = {}, {}
	for ext in (extlist or ""):lower():gmatch("[^|]+") do
		if not seen[ext] then
			seen[ext] = true
			out[#out + 1] = "*." .. ext
		end
	end
	return table.concat(out, " ")
end

--- The image name PyUI looks up for a ROM file
function romscan.imageBaseName(fileName, extSet)
	local base = util.splitext(fileName)
	while true do
		local nextBase, nextExt = util.splitext(base)
		if nextExt ~= "" and extSet[nextExt:lower()] then
			base = nextBase
		else
			return base
		end
	end
end

local function isImgsDir(name)
	return name == "Imgs" or name:sub(1, 5) == "Imgs_"
end

--- Every ROM under folderPath as { path, rel, name }; rel is the subfolder path ("" at the top)
function romscan.scanFolder(fs, folderPath, extSet, scanSubfolders)
	local roms = {}
	local function walk(dir, rel, depth)
		local entries = fs.list(dir)
		if not entries then
			return
		end
		table.sort(entries, function(a, b)
			return a.name < b.name
		end)
		for _, e in ipairs(entries) do
			if e.name:sub(1, 1) ~= "." then
				local full = dir .. "/" .. e.name
				if e.isDir then
					if scanSubfolders and depth < romscan.MAX_DEPTH and not isImgsDir(e.name) then
						walk(full, rel == "" and e.name or (rel .. "/" .. e.name), depth + 1)
					end
				else
					local _, ext = util.splitext(e.name)
					if ext ~= "" and extSet[ext:lower()] then
						roms[#roms + 1] = { path = full, rel = rel, name = e.name }
					end
				end
			end
		end
	end
	walk(folderPath, "", 0)
	return roms
end

-- File names of a directory, listed once per scan. PyUI checks image names against the folder's
-- listing (utils/cached_exists.py), so on a FAT card too an image only counts under its exact name.
local function nameSet(fs, cache, dir)
	local set = cache[dir]
	if set == nil then
		set = {}
		for _, e in ipairs(fs.list(dir) or {}) do
			if not e.isDir then
				set[e.name] = true
			end
		end
		cache[dir] = set
	end
	return set
end

--- True when PyUI would already show an image for the ROM
function romscan.hasArt(fs, cache, folderPath, rel, imgBase)
	local dirs = { util.joinPath(folderPath, "Imgs", rel) }
	if rel ~= "" then
		dirs[2] = util.joinPath(folderPath, "Imgs")
	end
	for _, dir in ipairs(dirs) do
		local set = nameSet(fs, cache, dir)
		for _, ext in ipairs(romscan.IMAGE_EXTS) do
			if set[imgBase .. ext] then
				return true
			end
		end
	end
	return false
end

--- Where the scraped image goes: Roms/<SYS>/Imgs/<rel>/<name>.png
function romscan.targetPath(folderPath, rel, imgBase)
	return util.joinPath(folderPath, "Imgs", rel, imgBase .. ".png")
end

romscan.MEDIA_FOLDERS = {
	cover = "covers",
	screenshot = "screenshots",
	wheel = "wheels",
	marquee = "marquees",
}

--- Where a Skyscraper game list run writes a ROM's artwork of outputType inside mediaDir. The
--- EmulationStation frontend writes <media>/<type folder>/<completeBaseName>.png for a ROM in a
--- subfolder too (only ES-DE mirrors subfolders), so one run cannot hold two ROMs of one name.
function romscan.skyscraperOutput(mediaDir, outputType, fileName)
	local folder = romscan.MEDIA_FOLDERS[outputType] or "covers"
	return util.joinPath(mediaDir, folder, util.completeBaseName(fileName) .. ".png")
end

return romscan
