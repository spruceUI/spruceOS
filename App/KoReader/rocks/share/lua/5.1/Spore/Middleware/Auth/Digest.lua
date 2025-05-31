--
-- lua-Spore : <http://fperrad.github.com/lua-Spore/>
--

local error = error
local time = require 'os'.time
local format = require 'string'.format
local crypto = require 'crypto'
local digest = crypto.digest or crypto.evp.digest
local url = require 'socket.url'
local Protocols = require 'Spore.Protocols'


local _ENV = nil
local m = {}

--  see RFC-2617

function m.generate_nonce ()
    return format('%08x', time())
end

local function path_query (uri)
    local t = url.parse(uri)
    return url.build{ path = t.path, query = t.query }
end

function m:call (req)
    local function add_header ()
        self.nc = self.nc + 1
        local nc = format('%08X', self.nc)
        local cnonce = m.generate_nonce()
        local uri = path_query(req.url)
        local ha1, ha2, response
        ha1 = digest('md5', self.username .. ':'
                         .. self.realm .. ':'
                         .. self.password)
        ha2 = digest('md5', req.method .. ':'
                         .. uri)
        if self.qop then
            response = digest('md5', ha1 .. ':'
                                  .. self.nonce .. ':'
                                  .. nc .. ':'
                                  .. cnonce .. ':'
                                  .. self.qop .. ':'
                                  .. ha2)
        else
            response = digest('md5', ha1 .. ':'
                                  .. self.nonce .. ':'
                                  .. ha2)
        end
        local auth = 'Digest username="' .. self.username
                  .. '", realm="' .. self.realm
                  .. '", nonce="' .. self.nonce
                  .. '", uri="' .. uri
                  .. '", algorithm="' .. self.algorithm
                  .. '", nc=' .. nc
                  .. ', cnonce="' .. cnonce
                  .. '", response="' .. response
                  .. '", opaque="' .. self.opaque .. '"'
        if self.qop then
            auth = auth .. ', qop=' .. self.qop
        end
        req.headers['authorization'] = auth
    end  -- add_header

    if req.env.spore.authentication and self.username and self.password then
        if self.nonce then
            req:finalize()
            add_header()
        end

        return  function (res)
            if res.status == 401 and res.headers['www-authenticate'] then
                for k, v in res.headers['www-authenticate']:gmatch'(%w+)="([^"]*)"' do
                    self[k] = v
                end
                if self.qop then
                    for v in self.qop:gmatch'([%w%-]+)[,;]?' do
                        self.qop = v
                        if v == 'auth' then
                            break
                        end
                    end
                    if self.qop ~= 'auth' then
                        error(self.qop .. " is not supported")
                    end
                end
                if not self.algorithm then
                    self.algorithm = 'MD5'
                end
                if self.algorithm ~= 'MD5' then
                    error(self.algorithm .. " is not supported")
                end
                self.nc = 0
                add_header()
                return Protocols.request(req)
            end
            return res
        end
    end
end

return m
--
-- Copyright (c) 2011-2015 Francois Perrad
--
-- This library is licensed under the terms of the MIT/X11 license,
-- like Lua itself.
--
