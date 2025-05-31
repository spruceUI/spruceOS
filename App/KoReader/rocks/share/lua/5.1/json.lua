--[[
	Licensed according to the included 'LICENSE' document
	Author: Thomas Harning Jr <harningt@gmail.com>
]]
local decode = require("json.decode")
local encode = require("json.encode")
local util = require("json.util")

local _G = _G

local _ENV = nil

local json = {
	_VERSION = "1.3.4",
	_DESCRIPTION = "LuaJSON : customizable JSON decoder/encoder",
	_COPYRIGHT = "Copyright (c) 2007-2017 Thomas Harning Jr. <harningt@gmail.com>",
	decode = decode,
	encode = encode,
	util = util
}

_G.json = json

return json
