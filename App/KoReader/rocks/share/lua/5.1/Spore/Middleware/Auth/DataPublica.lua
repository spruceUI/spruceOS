--
-- lua-Spore : <http://fperrad.github.com/lua-Spore/>
--

--[[
    See http://www.data-publica.com/content/api/
]]

local pairs = pairs
local tconcat = require 'table'.concat
local tsort = require 'table'.sort
local crypto = require 'crypto'
local digest = crypto.digest or crypto.evp.digest
local url = require 'socket.url'
local request = require 'Spore.Protocols'.request
require 'Spore'.early_validate = false

local _ENV = nil
local m = {}

function m:call (req)
    local env = req.env
    local spore = env.spore
    local params = spore.params

     local function get_string_to_sign ()
        local u = url.parse(req.url)
        u.query = nil
        local t = { url.build(u) }      -- url without query

        local names = {}
        for k in pairs(params) do
            if k ~= 'reference' and k ~= 'tablename' then
                names[#names+1] = k
            end
        end
        tsort(names)
        for i = 1, #names do
            local name = names[i]
            t[#t+1] = name .. '=' .. spore.params[name]
        end
        t[#t+1] = self.password
        return tconcat(t, ',')
    end -- get_string_to_sign

    if spore.authentication and self.key and self.password then
        params.format = params.format or 'json'
        params.limit = params.limit or 50
        params.offset = params.offset or 0
        params.key = self.key

        req:finalize()
        req.url = req.url .. '&signature=' .. digest('sha1', get_string_to_sign())

        return request(req)
    end
end

return m

--
-- Copyright (c) 2012-2015 Francois Perrad
--
-- This library is licensed under the terms of the MIT/X11 license,
-- like Lua itself.
--
