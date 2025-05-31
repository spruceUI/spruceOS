--[[
	Licensed according to the included 'LICENSE' document
	Author: Thomas Harning Jr <harningt@gmail.com>
]]
local lpeg = require("lpeg")
local select = select
local pairs, ipairs = pairs, ipairs
local tonumber = tonumber
local string_char = require("string").char
local rawset = rawset
local jsonutil = require("json.util")

local error = error
local setmetatable = setmetatable

local table_concat = require("table").concat

local merge = require("json.util").merge

local _ENV = nil

local function get_invalid_character_info(input, index)
	local parsed = input:sub(1, index)
	local bad_character = input:sub(index, index)
	local _, line_number = parsed:gsub('\n',{})
	local last_line = parsed:match("\n([^\n]+.)$") or parsed
	return line_number, #last_line, bad_character, last_line
end

local function build_report(msg)
	local fmt = msg:gsub("%%", "%%%%") .. " @ character: %i %i:%i [%s] line:\n%s"
	return lpeg.P(function(data, pos)
		local line, line_index, bad_char, last_line = get_invalid_character_info(data, pos)
		local text = fmt:format(pos, line, line_index, bad_char, last_line)
		error(text)
	end) * 1
end
local function unexpected()
	local msg = "unexpected character"
	return build_report(msg)
end
local function denied(item, option)
	local msg
	if option then
		msg = ("'%s' denied by option set '%s'"):format(item, option)
	else
		msg = ("'%s' denied"):format(item)
	end
	return build_report(msg)
end

-- 09, 0A, 0B, 0C, 0D, 20
local ascii_space = lpeg.S("\t\n\v\f\r ")
local unicode_space
do
	local chr = string_char
	local u_space = ascii_space
	-- \u0085 \u00A0
	u_space = u_space + lpeg.P(chr(0xC2)) * lpeg.S(chr(0x85) .. chr(0xA0))
	-- \u1680 \u180E
	u_space = u_space + lpeg.P(chr(0xE1)) * (lpeg.P(chr(0x9A, 0x80)) + chr(0xA0, 0x8E))
	-- \u2000 - \u200A, also 200B
	local spacing_end = ""
	for i = 0x80,0x8b do
		spacing_end = spacing_end .. chr(i)
	end
	-- \u2028 \u2029 \u202F
	spacing_end = spacing_end .. chr(0xA8) .. chr(0xA9) .. chr(0xAF)
	u_space = u_space + lpeg.P(chr(0xE2, 0x80)) * lpeg.S(spacing_end)
	-- \u205F
	u_space = u_space + lpeg.P(chr(0xE2, 0x81, 0x9F))
	-- \u3000
	u_space = u_space + lpeg.P(chr(0xE3, 0x80, 0x80))
	-- BOM \uFEFF
	u_space = u_space + lpeg.P(chr(0xEF, 0xBB, 0xBF))
	unicode_space = u_space
end

local identifier = lpeg.R("AZ","az","__") * lpeg.R("AZ","az", "__", "09") ^0

local hex = lpeg.R("09","AF","af")
local hexpair = hex * hex

local comments = {
	cpp = lpeg.P("//") * (1 - lpeg.P("\n"))^0 * lpeg.P("\n"),
	c = lpeg.P("/*") * (1 - lpeg.P("*/"))^0 * lpeg.P("*/")
}

local comment = comments.cpp + comments.c

local ascii_ignored = (ascii_space + comment)^0

local unicode_ignored = (unicode_space + comment)^0

-- Parse the lpeg version skipping patch-values
-- LPEG <= 0.7 have no version value... so 0.7 is value
local DecimalLpegVersion = lpeg.version and tonumber(lpeg.version():match("^(%d+%.%d+)")) or 0.7

local function setObjectKeyForceNumber(t, key, value)
	key = tonumber(key) or key
	return rawset(t, key, value)
end

local util = {
	unexpected = unexpected,
	denied = denied,
	ascii_space = ascii_space,
	unicode_space = unicode_space,
	identifier = identifier,
	hex = hex,
	hexpair = hexpair,
	comments = comments,
	comment = comment,
	ascii_ignored = ascii_ignored,
	unicode_ignored = unicode_ignored,
	DecimalLpegVersion = DecimalLpegVersion,
	get_invalid_character_info = get_invalid_character_info,
	setObjectKeyForceNumber = setObjectKeyForceNumber
}

return util
