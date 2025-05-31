--
-- lua-Spore : <http://fperrad.github.com/lua-Spore/>
--

local pairs = pairs
local setmetatable = setmetatable
local tostring = tostring
local require = require
local string = string
local tconcat = require 'table'.concat
local url = require 'socket.url'


local _ENV = nil
local m = {}
local mt = { __index = m }

m.redirect = false

function m.new (env)
    local obj = {
        env = env,
        redirect = m.redirect,
        headers = {
            ['user-agent'] = env.HTTP_USER_AGENT,
        },
    }
    return setmetatable(obj, mt)
end

local function escape (s)
    -- see RFC 3986 & RFC 5849
    -- unreserved
    return string.gsub(s, '[^-._~%w]', function(c)
        return string.format('%%%02X', string.byte(c))
    end)
end
m.escape = escape

local function escape_path (s)
    -- see RFC 3986
    -- unreserved + slash
    return string.gsub(s, '[^-._~%w/]', function(c)
        return string.format('%%%02X', string.byte(c))
    end)
end

function m:finalize (oauth)
    local function gsub2 (s, patt1, patt2, repl)
        repl = repl:gsub('%%', '%%%%')
        local r, n = s:gsub(patt1, repl)
        if n == 0 then
            r, n = s:gsub(patt2, repl)
        end
        return r, n
    end -- gsub2

    if self.url then
        return
    end
    local env = self.env
    local spore = env.spore
    local payload = spore.method.payload or {}
    if not require 'Spore'.early_validate then
        require 'Spore'.validate(spore.caller, spore.method, spore.params, spore.payload)
    end
    local path_info = env.PATH_INFO
    local query_string = env.QUERY_STRING
    local form_data = {}
    for k, v in pairs(spore.form_data or {}) do
        form_data[tostring(k)] = tostring(v)
    end
    local headers = {}
    for k, v in pairs(spore.headers or {}) do
        headers[tostring(k):lower()] = tostring(v)
    end
    local query = {}
    if query_string then
        query[1] = query_string
    end
    local form = {}
    for k, v in pairs(spore.params) do
        k = tostring(k)
        v = tostring(v)
        local patt = ':' .. k
        local patt6570 = '{' .. k .. '}'        -- see RFC 6570
        local n
        path_info, n = gsub2(path_info, patt, patt6570, escape_path(v))
        for kk, vv in pairs(form_data) do
            local nn
            vv, nn = gsub2(vv, patt, patt6570, v)
            if nn > 0 then
                form_data[kk] = vv
                form[kk] = vv
                n = n + 1
            end
        end
        for kk, vv in pairs(headers) do
            local nn
            vv, nn = gsub2(vv, patt, patt6570, v)
            if nn > 0 then
                headers[kk] = vv
                self.headers[kk] = vv
                n = n + 1
            end
        end
        for i = 1, #payload do
            if k == payload[i] then
                n = n + 1
            end
        end
        if n == 0 then
            query[#query+1] = escape(k) .. '=' .. escape(v)
        end
    end
    if #query > 0 then
        query_string = tconcat(query, '&')
    end
    env.PATH_INFO = path_info
    env.QUERY_STRING = query_string
    if spore.form_data then
        spore.form_data = form
    end
    self.method = env.REQUEST_METHOD
    self.url = url.build {
        scheme  = spore.url_scheme,
        host    = env.SERVER_NAME,
        port    = env.SERVER_PORT,
        path    = path_info,
        query   = query_string,
    }
end

return m
--
-- Copyright (c) 2010-2018 Francois Perrad
--
-- This library is licensed under the terms of the MIT/X11 license,
-- like Lua itself.
--
