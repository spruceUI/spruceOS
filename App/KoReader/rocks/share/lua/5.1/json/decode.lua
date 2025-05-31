--[[
	Licensed according to the included 'LICENSE' document
	Author: Thomas Harning Jr <harningt@gmail.com>
]]
local lpeg = require("lpeg")

local error = error
local pcall = pcall

local jsonutil = require("json.util")
local merge = jsonutil.merge
local util = require("json.decode.util")

local decode_state = require("json.decode.state")

local setmetatable, getmetatable = setmetatable, getmetatable
local assert = assert
local ipairs, pairs = ipairs, pairs
local string_char = require("string").char

local type = type

local require = require

local _ENV = nil

local modulesToLoad = {
	"composite",
	"strings",
	"number",
	"others"
}
local loadedModules = {
}

local json_decode = {}

json_decode.default = {
	unicodeWhitespace = true,
	initialObject = false,
	nothrow = false
}

local modes_defined = { "default", "strict", "simple" }

json_decode.simple = {}

json_decode.strict = {
	unicodeWhitespace = true,
	initialObject = true,
	nothrow = false
}

for _,name in ipairs(modulesToLoad) do
	local mod = require("json.decode." .. name)
	if mod.mergeOptions then
		for _, mode in pairs(modes_defined) do
			mod.mergeOptions(json_decode[mode], mode)
		end
	end
	loadedModules[#loadedModules + 1] = mod
end

-- Shift over default into defaultOptions to permit build optimization
local defaultOptions = json_decode.default
json_decode.default = nil

local function generateDecoder(lexer, options)
	-- Marker to permit detection of final end
	local marker = {}
	local parser = lpeg.Ct((options.ignored * lexer)^0 * lpeg.Cc(marker)) * options.ignored * (lpeg.P(-1) + util.unexpected())
	local decoder = function(data)
		local state = decode_state.create(options)
		local parsed = parser:match(data)
		assert(parsed, "Invalid JSON data")
		local i = 0
		while true do
			i = i + 1
			local item = parsed[i]
			if item == marker then break end
			if type(item) == 'function' and item ~= jsonutil.undefined and item ~= jsonutil.null then
				item(state)
			else
				state:set_value(item)
			end
		end
		if options.initialObject then
			assert(type(state.previous) == 'table', "Initial value not an object or array")
		end
		-- Make sure stack is empty
		assert(state.i == 0, "Unclosed elements present")
		return state.previous
	end
	if options.nothrow then
		return function(data)
			local status, rv = pcall(decoder, data)
			if status then
				return rv
			else
				return nil, rv
			end
		end
	end
	return decoder
end

local function buildDecoder(mode)
	mode = mode and merge({}, defaultOptions, mode) or defaultOptions
	for _, mod in ipairs(loadedModules) do
		if mod.mergeOptions then
			mod.mergeOptions(mode)
		end
	end
	local ignored = mode.unicodeWhitespace and util.unicode_ignored or util.ascii_ignored
	-- Store 'ignored' in the global options table
	mode.ignored = ignored

	--local grammar = {
	--	[1] = mode.initialObject and (ignored * (object_type + array_type)) or value_type
	--}
	local lexer
	for _, mod in ipairs(loadedModules) do
		local new_lexer = mod.generateLexer(mode)
		lexer = lexer and lexer + new_lexer or new_lexer
	end
	return generateDecoder(lexer, mode)
end

-- Since 'default' is nil, we cannot take map it
local defaultDecoder = buildDecoder(json_decode.default)
local prebuilt_decoders = {}
for _, mode in pairs(modes_defined) do
	if json_decode[mode] ~= nil then
		prebuilt_decoders[json_decode[mode]] = buildDecoder(json_decode[mode])
	end
end

--[[
Options:
	number => number decode options
	string => string decode options
	array  => array decode options
	object => object decode options
	initialObject => whether or not to require the initial object to be a table/array
	allowUndefined => whether or not to allow undefined values
]]
local function getDecoder(mode)
	mode = mode == true and json_decode.strict or mode or json_decode.default
	local decoder = mode == nil and defaultDecoder or prebuilt_decoders[mode]
	if decoder then
		return decoder
	end
	return buildDecoder(mode)
end

local function decode(data, mode)
	local decoder = getDecoder(mode)
	return decoder(data)
end

local mt = {}
mt.__call = function(self, ...)
	return decode(...)
end

json_decode.getDecoder = getDecoder
json_decode.decode = decode
json_decode.util = util
setmetatable(json_decode, mt)

return json_decode
