--- Box art region choice -> Skyscraper region settings
---
--- ScreenScraper keeps a cover per region; Skyscraper walks a region priority list and takes the
--- first region that has the artwork. "Auto" puts the region found in the file name first
--- ("Game (Europe).zip" gets the European box), then spruce's preferredRegion (system json,
--- default "USA", the same key PyUI's own box art scraper reads). A fixed choice ignores file
--- names. Region keys are Skyscraper's (docs/REGIONS.md).
local regions = {}

regions.CHOICES = { "Auto", "USA", "Europe", "Japan", "World" }

local KEYS = { USA = "us", Europe = "eu", Japan = "jp", World = "wor" }

-- Skyscraper's internal default order; every list below ends with whatever it leaves out
local DEFAULT = {
	"eu", "us", "ss", "uk", "wor", "jp", "au", "ame", "de", "cus", "cn", "kr", "asi", "br", "sp",
	"fr", "gr", "it", "no", "dk", "nz", "nl", "pl", "ru", "se", "tw", "ca",
}

local FIRST = {
	us = { "us", "wor", "ame", "ca", "ss", "eu", "uk", "au" },
	eu = { "eu", "wor", "uk", "de", "fr", "sp", "it", "au", "ss", "us" },
	jp = { "jp", "wor", "asi", "ss", "us", "eu" },
	wor = { "wor", "us", "eu", "ss", "uk", "jp" },
}

--- Region key for spruce's preferredRegion value ("USA", "EUROPE", "JAPAN", "WORLD", ...)
function regions.keyForSpruce(value)
	local v = type(value) == "string" and value:upper() or ""
	if v:find("EUR", 1, true) or v == "EU" then
		return "eu"
	elseif v:find("JAP", 1, true) or v == "JPN" or v == "JP" then
		return "jp"
	elseif v:find("WORLD", 1, true) or v == "WOR" then
		return "wor"
	end
	return "us"
end

function regions.priorities(key)
	local out, seen = {}, {}
	for _, list in ipairs({ FIRST[key] or FIRST.us, DEFAULT }) do
		for _, r in ipairs(list) do
			if not seen[r] then
				seen[r] = true
				out[#out + 1] = r
			end
		end
	end
	return out
end

--- Skyscraper [main] values for a choice. region forces the first region and turns file-name
--- detection off (both 3.17 and 3.21); regionFromFilename only exists from 3.20 and older
--- releases ignore it, they always put file-name regions first.
function regions.settings(choice, spruceRegion)
	local key = KEYS[choice]
	if key then
		return {
			region = key,
			regionPrios = table.concat(regions.priorities(key), ", "),
			regionFromFilename = "off",
		}
	end
	local preferred = regions.keyForSpruce(spruceRegion)
	return {
		regionPrios = table.concat(regions.priorities(preferred), ", "),
		regionFromFilename = "first",
	}
end

--- Text for the menu: "Auto (file name, then USA)"
function regions.describe(choice, spruceRegion)
	if KEYS[choice] then
		return choice
	end
	local names = { us = "USA", eu = "Europe", jp = "Japan", wor = "World" }
	return "Auto (" .. names[regions.keyForSpruce(spruceRegion)] .. ")"
end

return regions
