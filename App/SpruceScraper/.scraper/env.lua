--- Paths and device facts from spruce/launch.sh (see docs/DEVELOPMENT.md, "Environment contract")
local json = require("lib.json")

local env = {}

local function get(key, default)
	local v = os.getenv(key)
	if v == nil or v == "" then
		return default
	end
	return v
end

local function readJson(path)
	if not path then
		return nil
	end
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local raw = f:read("*a")
	f:close()
	local ok, data = pcall(json.decode, raw)
	if ok and type(data) == "table" then
		return data
	end
	return nil
end

function env.load()
	local source = get("SOURCE_DIR", love.filesystem.getSource())
	local root = get("ROOT_DIR", source)
	local roots = {}
	for p in get("SCRAPER_ROMS_DIRS", "/mnt/SDCARD/Roms:/media/sdcard1/Roms"):gmatch("[^:]+") do
		roots[#roots + 1] = p
	end
	local systemJson = get("SPRUCE_SYSTEM_JSON", nil)
	local system = readJson(systemJson) or {}
	return {
		root = root,
		source = source,
		userdata = get("SCRAPER_USERDATA", root .. "/userdata"),
		emu = get("SCRAPER_EMU_DIR", "/mnt/SDCARD/Emu"),
		romRoots = roots,
		skyscraper = get("SCRAPER_SKYSCRAPER_DIR", source .. "/skyscraper"),
		python = get("SCRAPER_PYTHON", nil),
		baseLibraryPath = get("SCRAPER_BASE_LD_LIBRARY_PATH", ""),
		pyuiTrigger = get("SCRAPER_PYUI_TRIGGER", "/mnt/SDCARD/App/PyUI/pyui_resize_boxart_trigger"),
		accountFile = get("SCRAPER_ACCOUNT_FILE", root .. "/screenscraper.txt"),
		-- CA certificates for Skyscraper's HTTPS; spruce ships a bundle, firmware may not
		caFile = get("SCRAPER_CA_FILE", "/mnt/SDCARD/spruce/etc/ca-certificates.crt"),
		-- network and clock check before Skyscraper runs; dev_launch.sh turns it off for the fake
		preflight = get("SCRAPER_PREFLIGHT", "1") ~= "0",
		-- same key and default PyUI's own box art scraper uses
		spruceRegion = type(system.preferredRegion) == "string" and system.preferredRegion or "USA",
		platform = get("SPRUCE_PLATFORM", "unknown"),
		spruceVersion = get("SPRUCE_VERSION", ""),
	}
end

return env
