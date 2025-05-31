--[[
	Licensed according to the included 'LICENSE' document
	Author: Thomas Harning Jr <harningt@gmail.com>
]]
local tostring = tostring
local assert = assert
local jsonutil = require("json.util")
local huge = require("math").huge

local _ENV = nil

local defaultOptions = {
	nan = true,
	inf = true
}

local modeOptions = {}
modeOptions.strict = {
	nan = false,
	inf = false
}

local function mergeOptions(options, mode)
	jsonutil.doOptionMerge(options, false, 'number', defaultOptions, mode and modeOptions[mode])
end


local function encodeNumber(number, options)
	if number ~= number then
		assert(options.nan, "Invalid number: NaN not enabled")
		return "NaN"
	end
	if number == huge then
		assert(options.inf, "Invalid number: Infinity not enabled")
		return "Infinity"
	end
	if number == -huge then
		assert(options.inf, "Invalid number: Infinity not enabled")
		return "-Infinity"
	end
	return tostring(number)
end

local function getEncoder(options)
	options = options and jsonutil.merge({}, defaultOptions, options) or defaultOptions
	return {
		number = function(number, state)
			return encodeNumber(number, options)
		end
	}
end

local number = {
	mergeOptions = mergeOptions,
	getEncoder = getEncoder
}

return number
