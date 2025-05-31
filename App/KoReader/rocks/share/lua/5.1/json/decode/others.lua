--[[
	Licensed according to the included 'LICENSE' document
	Author: Thomas Harning Jr <harningt@gmail.com>
]]
local lpeg = require("lpeg")
local jsonutil = require("json.util")
local merge = jsonutil.merge
local util = require("json.decode.util")

-- Container module for other JavaScript types (bool, null, undefined)

local _ENV = nil

-- For null and undefined, use the util.null value to preserve null-ness
local booleanCapture =
	lpeg.P("true") * lpeg.Cc(true)
	+ lpeg.P("false") * lpeg.Cc(false)

local nullCapture = lpeg.P("null")
local undefinedCapture = lpeg.P("undefined")

local defaultOptions = {
	allowUndefined = true,
	null = jsonutil.null,
	undefined = jsonutil.undefined
}

local modeOptions = {}

modeOptions.simple = {
	null = false,     -- Mapped to nil
	undefined = false -- Mapped to nil
}
modeOptions.strict = {
	allowUndefined = false
}

local function mergeOptions(options, mode)
	jsonutil.doOptionMerge(options, false, 'others', defaultOptions, mode and modeOptions[mode])
end

local function generateLexer(options)
	-- The 'or nil' clause allows false to map to a nil value since 'nil' cannot be merged
	options = options.others
	local valueCapture = (
		booleanCapture
		+ nullCapture * lpeg.Cc(options.null or nil)
	)
	if options.allowUndefined then
		valueCapture = valueCapture + undefinedCapture * lpeg.Cc(options.undefined or nil)
	else
		valueCapture = valueCapture + #undefinedCapture * util.denied("undefined", "others.allowUndefined")
	end
	return valueCapture
end

local others = {
	mergeOptions = mergeOptions,	
	generateLexer = generateLexer
}

return others
