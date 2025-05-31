--
-- lua-Spore : <http://fperrad.github.com/lua-Spore/>
--

local pcall = pcall
local type = type
local raises = require 'Spore'.raises
local yaml = require 'lyaml'


local _ENV = nil
local m = {}

m['content-type'] = 'text/x-yaml'

function m:call (req)
    local spore = req.env.spore
    if spore.payload and type(spore.payload) == 'table' then
        spore.payload = yaml.dump({ spore.payload })
        req.headers['content-type'] = m['content-type']
    end
    req.headers['accept'] = m['content-type']
    return  function (res)
                if type(res.body) == 'string' and res.body:match'%S' then
                    local r, msg = pcall(function ()
                        res.body = yaml.load(res.body)
                    end)
                    if not r then
                        if spore.errors then
                            spore.errors:write(msg)
                            spore.errors:write(res.body, "\n")
                        end
                        if res.status == 200 then
                            raises(res, msg)
                        end
                    end
                end
                return res
            end
end

return m
--
-- Copyright (c) 2010-2016 Francois Perrad
--
-- This library is licensed under the terms of the MIT/X11 license,
-- like Lua itself.
--
