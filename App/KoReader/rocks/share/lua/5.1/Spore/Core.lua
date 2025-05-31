
--
-- lua-Spore : <http://fperrad.github.com/lua-Spore/>
--

local assert = assert
local require = require
local select = select
local type = type
local coroutine = require 'coroutine'
local Request = require 'Spore.Request'
local Protocols = require 'Spore.Protocols'


local _ENV = nil
local m = {}

local function _enable_if (self, cond, mw, args)
    if not mw:match'^Spore%.Middleware%.' then
        mw = 'Spore.Middleware.' .. mw
    end
    local _m = require(mw)
    assert(type(_m.call) == 'function', mw .. " without a function call")
    local f = function (req)
        local res = _m.call(args, req)
        if type(res) == 'thread' then
            coroutine.yield()
            res = select(2, coroutine.resume(res))
        end
        return res
    end
    local t = self.middlewares; t[#t+1] = { cond = cond, code = f }
end

function m:enable_if (cond, mw, args)
    local checktype = require 'Spore'.checktype
    checktype('enable_if', 2, cond, 'function')
    checktype('enable_if', 3, mw, 'string')
    args = args or {}
    checktype('enable_if', 4, args, 'table')
    return _enable_if(self, cond, mw, args)
end

function m:enable (mw, args)
    local checktype = require 'Spore'.checktype
    checktype('enable', 2, mw, 'string')
    args = args or {}
    checktype('enable', 3, args, 'table')
    return _enable_if(self, function () return true end, mw, args)
end

function m:reset_middlewares ()
    self.middlewares = {}
end

function m:http_request (env)
    local req = Request.new(env)
    local callbacks = {}
    local response
    local middlewares = self.middlewares
    for i = 1, #middlewares do
        local mw = middlewares[i]
        if mw.cond(req) then
            local res = mw.code(req)
            if type(res) == 'function' then
                callbacks[#callbacks+1] = res
            elseif res then
                if res.status == 599 then
                    return res
                end
                response = res
                break
            end
        end
    end

    if response == nil then
        req:finalize()
        response = Protocols.request(req)
    end

    for i = #callbacks, 1, -1 do
        local cb = callbacks[i]
        response = cb(response)
    end

    return response
end

return m
--
-- Copyright (c) 2010-2018 Francois Perrad
--
-- This library is licensed under the terms of the MIT/X11 license,
-- like Lua itself.
--
