--[[
	Licensed according to the included 'LICENSE' document
	Author: Thomas Harning Jr <harningt@gmail.com>
]]
local pairs = pairs
local type = type

local lpeg = require("lpeg")

local util = require("json.decode.util")
local jsonutil = require("json.util")

local rawset = rawset

local assert = assert
local tostring = tostring

local error = error
local getmetatable = getmetatable

local _ENV = nil

local defaultOptions = {
	array = {
		allowEmptyElement = false,
		trailingComma = true
	},
	object = {
		allowEmptyElement = false,
		trailingComma = true,
		number = true,
		identifier = true,
		setObjectKey = rawset
	},
	calls = {
		allowEmptyElement = false,
		defs = nil,
		-- By default, do not allow undefined calls to be de-serialized as call objects
		allowUndefined = false,
		trailingComma = true
	}
}

local modeOptions = {
	default = nil,
	strict = {
		array = {
			trailingComma = false
		},
		object = {
			trailingComma = false,
			number = false,
			identifier = false
		}
	}
}

local function BEGIN_ARRAY(state)
	state:push()
	state:new_array()
end
local function END_ARRAY(state)
	state:end_array()
	state:pop()
end

local function BEGIN_OBJECT(state)
	state:push()
	state:new_object()
end
local function END_OBJECT(state)
	state:end_object()
	state:pop()
end

local function END_CALL(state)
	state:end_call()
	state:pop()
end

local function SET_KEY(state)
	state:set_key()
end

local function NEXT_VALUE(state)
	state:put_value()
end

local function mergeOptions(options, mode)
	jsonutil.doOptionMerge(options, true, 'array', defaultOptions, mode and modeOptions[mode])
	jsonutil.doOptionMerge(options, true, 'object', defaultOptions, mode and modeOptions[mode])
	jsonutil.doOptionMerge(options, true, 'calls', defaultOptions, mode and modeOptions[mode])
end


local isPattern
if lpeg.type then
	function isPattern(value)
		return lpeg.type(value) == 'pattern'
	end
else
	local metaAdd = getmetatable(lpeg.P("")).__add
	function isPattern(value)
		return getmetatable(value).__add == metaAdd
	end
end


local function generateSingleCallLexer(name, func)
	if type(name) ~= 'string' and not isPattern(name) then
		error("Invalid functionCalls name: " .. tostring(name) .. " not a string or LPEG pattern")
	end
	-- Allow boolean or function to match up w/ encoding permissions
	if type(func) ~= 'boolean' and type(func) ~= 'function' then
		error("Invalid functionCalls item: " .. name .. " not a function")
	end
	local function buildCallCapture(name)
		return function(state)
			if func == false then
				error("Function call on '" .. name .. "' not permitted")
			end
			state:push()
			state:new_call(name, func)
		end
	end
	local nameCallCapture
	if type(name) == 'string' then
		nameCallCapture = lpeg.P(name .. "(") * lpeg.Cc(name) / buildCallCapture
	else
		-- Name matcher expected to produce a capture
		nameCallCapture = name * "(" / buildCallCapture
	end
	-- Call func over nameCallCapture and value to permit function receiving name
	return nameCallCapture
end

local function generateNamedCallLexers(options)
	if not options.calls or not options.calls.defs then
		return
	end
	local callCapture
	for name, func in pairs(options.calls.defs) do
		local newCapture = generateSingleCallLexer(name, func)
		if not callCapture then
			callCapture = newCapture
		else
			callCapture = callCapture + newCapture
		end
	end
	return callCapture
end

local function generateCallLexer(options)
	local lexer
	local namedCapture = generateNamedCallLexers(options)
	if options.calls and options.calls.allowUndefined then
		lexer = generateSingleCallLexer(lpeg.C(util.identifier), true)
	end
	if namedCapture then
		lexer = lexer and lexer + namedCapture or namedCapture
	end
	if lexer then
		lexer = lexer + lpeg.P(")") * lpeg.Cc(END_CALL)
	end
	return lexer
end

local function generateLexer(options)
	local ignored = options.ignored
	local array_options, object_options = options.array, options.object
	local lexer =
		lpeg.P("[") * lpeg.Cc(BEGIN_ARRAY)
		+ lpeg.P("]") * lpeg.Cc(END_ARRAY)
		+ lpeg.P("{") * lpeg.Cc(BEGIN_OBJECT)
		+ lpeg.P("}") * lpeg.Cc(END_OBJECT)
		+ lpeg.P(":") * lpeg.Cc(SET_KEY)
		+ lpeg.P(",") * lpeg.Cc(NEXT_VALUE)
	if object_options.identifier then
		-- Add identifier match w/ validation check that it is in key
		lexer = lexer + lpeg.C(util.identifier) * ignored * lpeg.P(":") * lpeg.Cc(SET_KEY)
	end
	local callLexers = generateCallLexer(options)
	if callLexers then
		lexer = lexer + callLexers
	end
	return lexer
end

local composite = {
	mergeOptions = mergeOptions,
	generateLexer = generateLexer
}

return composite
