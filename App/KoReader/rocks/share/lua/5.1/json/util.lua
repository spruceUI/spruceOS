--[[
	Licensed according to the included 'LICENSE' document
	Author: Thomas Harning Jr <harningt@gmail.com>
]]
local type = type
local print = print
local tostring = tostring
local pairs = pairs
local getmetatable, setmetatable = getmetatable, setmetatable
local select = select

local _ENV = nil

local function foreach(tab, func)
	for k, v in pairs(tab) do
		func(k,v)
	end
end
local function printValue(tab, name)
        local parsed = {}
        local function doPrint(key, value, space)
                space = space or ''
                if type(value) == 'table' then
                        if parsed[value] then
                                print(space .. key .. '= <' .. parsed[value] .. '>')
                        else
                                parsed[value] = key
                                print(space .. key .. '= {')
                                space = space .. ' '
                                foreach(value, function(key, value) doPrint(key, value, space) end)
                        end
                else
					if type(value) == 'string' then
						value = '[[' .. tostring(value) .. ']]'
					end
					print(space .. key .. '=' .. tostring(value))
                end
        end
        doPrint(name, tab)
end

local function clone(t)
	local ret = {}
	for k,v in pairs(t) do
		ret[k] = v
	end
	return ret
end

local function inner_merge(t, remaining, from, ...)
	if remaining == 0 then
		return t
	end
	if from then
		for k,v in pairs(from) do
			t[k] = v
		end
	end
	return inner_merge(t, remaining - 1, ...)
end

--[[*
    Shallow-merges tables in order onto the first table.

    @param t table to merge entries onto
    @param ... sequence of 0 or more tables to merge onto 't'

    @returns table 't' from input
]]
local function merge(t, ...)
	return inner_merge(t, select('#', ...), ...)
end

-- Function to insert nulls into the JSON stream
local function null()
	return null
end

-- Marker for 'undefined' values
local function undefined()
	return undefined
end

local ArrayMT = {}

--[[
	Return's true if the metatable marks it as an array..
	Or false if it has no array component at all
	Otherwise nil to get the normal detection component working
]]
local function IsArray(value)
	if type(value) ~= 'table' then return false end
	local meta = getmetatable(value)
	local ret = meta == ArrayMT or (meta ~= nil and meta.__is_luajson_array)
	if not ret then
		if #value == 0 then return false end
	else
		return ret
	end
end
local function InitArray(array)
	setmetatable(array, ArrayMT)
	return array
end

local CallMT = {}

local function isCall(value)
	return CallMT == getmetatable(value)
end

local function buildCall(name, ...)
	local callData = {
		name = name,
		parameters = {n = select('#', ...), ...}
	}
	return setmetatable(callData, CallMT)
end

local function decodeCall(callData)
	if not isCall(callData) then return nil end
	return callData.name, callData.parameters
end

local function doOptionMerge(options, nested, name, defaultOptions, modeOptions)
	if nested then
		modeOptions = modeOptions and modeOptions[name]
		defaultOptions = defaultOptions and defaultOptions[name]
	end
	options[name] = merge(
		{},
		defaultOptions,
		modeOptions,
		options[name]
	)
end

local json_util = {
	printValue = printValue,
	clone = clone,
	merge = merge,
	null = null,
	undefined = undefined,
	IsArray = IsArray,
	InitArray = InitArray,
	isCall = isCall,
	buildCall = buildCall,
	decodeCall = decodeCall,
	doOptionMerge = doOptionMerge
}

return json_util
