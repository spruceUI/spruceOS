--[[
	Licensed according to the included 'LICENSE' document
	Author: Thomas Harning Jr <harningt@gmail.com>
]]
local lpeg = require("lpeg")
local tonumber = tonumber
local jsonutil = require("json.util")
local merge = jsonutil.merge
local util = require("json.decode.util")

local _ENV = nil

local digit  = lpeg.R("09")
local digits = digit^1

-- Illegal octal declaration
local illegal_octal_detect = #(lpeg.P('0') * digits) * util.denied("Octal numbers")

local int = (lpeg.P('-') + 0) * (lpeg.R("19") * digits + illegal_octal_detect + digit)

local frac = lpeg.P('.') * digits

local exp = lpeg.S("Ee") * (lpeg.S("-+") + 0) * digits

local nan = lpeg.S("Nn") * lpeg.S("Aa") * lpeg.S("Nn")
local inf = lpeg.S("Ii") * lpeg.P("nfinity")
local ninf = lpeg.P('-') * lpeg.S("Ii") * lpeg.P("nfinity")
local hex = (lpeg.P("0x") + lpeg.P("0X")) * lpeg.R("09","AF","af")^1

local defaultOptions = {
	nan = true,
	inf = true,
	frac = true,
	exp = true,
	hex = false
}

local modeOptions = {}

modeOptions.strict = {
	nan = false,
	inf = false
}

local nan_value = 0/0
local inf_value = 1/0
local ninf_value = -1/0

--[[
	Options: configuration options for number rules
		nan: match NaN
		inf: match Infinity
	   frac: match fraction portion (.0)
	    exp: match exponent portion  (e1)
	DEFAULT: nan, inf, frac, exp
]]
local function mergeOptions(options, mode)
	jsonutil.doOptionMerge(options, false, 'number', defaultOptions, mode and modeOptions[mode])
end

local function generateLexer(options)
	options = options.number
	local ret = int
	if options.frac then
		ret = ret * (frac + 0)
	else
		ret = ret * (#frac * util.denied("Fractions", "number.frac") + 0)
	end
	if options.exp then
		ret = ret * (exp + 0)
	else
		ret = ret * (#exp * util.denied("Exponents", "number.exp") + 0)
	end
	if options.hex then
		ret = hex + ret
	else
		ret = #hex * util.denied("Hexadecimal", "number.hex") + ret
	end
	-- Capture number now
	ret = ret / tonumber
	if options.nan then
		ret = ret + nan / function() return nan_value end
	else
		ret = ret + #nan * util.denied("NaN", "number.nan")
	end
	if options.inf then
		ret = ret + ninf / function() return ninf_value end + inf / function() return inf_value end
	else
		ret = ret + (#ninf + #inf) * util.denied("+/-Inf", "number.inf")
	end
	return ret
end

local number = {
	int = int,
	mergeOptions = mergeOptions,
	generateLexer = generateLexer
}

return number
