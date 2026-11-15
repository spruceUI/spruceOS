--- Settings kept in userdata/settings.json
---
--- The ScreenScraper password is stored in plain text, as Skyscraper and Scrappy store it:
--- Skyscraper needs it on every run. It never leaves the card except in requests to ScreenScraper.
local json = require("lib.json")

local settings = {}

settings.DEFAULTS = {
	username = "",
	password = "",
	region = "Auto",
	threads = 0, -- 0 = what the ScreenScraper account allows
	overwrite = false,
	template = "boxart",
	excluded = {}, -- system name -> true for systems the user switched off
}

settings.values = {}
local filePath

local function copy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = copy(x)
	end
	return out
end

function settings.load(path)
	filePath = path
	settings.values = copy(settings.DEFAULTS)
	local f = io.open(path, "rb")
	if not f then
		return false
	end
	local raw = f:read("*a")
	f:close()
	local ok, data = pcall(json.decode, raw)
	if not ok or type(data) ~= "table" then
		return false
	end
	for key, default in pairs(settings.DEFAULTS) do
		if data[key] ~= nil and type(data[key]) == type(default) then
			settings.values[key] = data[key]
		end
	end
	return true
end

function settings.save()
	if not filePath then
		return false
	end
	local f = io.open(filePath .. ".part", "wb")
	if not f then
		return false
	end
	local excluded = {}
	for name, off in pairs(settings.values.excluded) do
		if off then
			excluded[name] = true
		end
	end
	local out = copy(settings.values)
	out.excluded = excluded
	f:write(json.encode(out))
	f:close()
	return os.rename(filePath .. ".part", filePath) and true or false
end

function settings.get(key)
	return settings.values[key]
end

function settings.set(key, value)
	settings.values[key] = value
	settings.save()
end

function settings.isSelected(name)
	return not settings.values.excluded[name]
end

function settings.setSelected(name, on)
	settings.values.excluded[name] = (not on) or nil
	settings.save()
end

--- Read a screenscraper.txt written on a PC ("username=..." and "password=..." lines), take the
--- account over and rename the file so it is read once. Returns the user name or nil.
function settings.importAccountFile(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local raw = f:read("*a")
	f:close()
	local user, pass
	for line in raw:gmatch("[^\r\n]+") do
		local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
		if key then
			key = key:lower()
			if key == "username" or key == "user" or key == "ssid" then
				user = value
			elseif key == "password" or key == "pass" or key == "sspassword" then
				pass = value
			end
		end
	end
	if not user or user == "" then
		return nil
	end
	settings.values.username = user
	settings.values.password = pass or ""
	settings.save()
	os.rename(path, path .. ".imported")
	return user
end

return settings
