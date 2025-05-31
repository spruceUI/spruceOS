--
-- lua-Spore : <http://fperrad.github.com/lua-Spore/>
--

local string = string
local socket = require 'socket' -- See http://lua-users.org/wiki/HiResTimers

local _ENV = nil
local m = {}

function m:call (req)
    local start_time = socket.gettime()

    return  function (res)
                local diff = socket.gettime() - start_time
                local str = string.format('%.4f', diff)
                local header = res.headers['x-spore-runtime']
                if header then
                    res.headers['x-spore-runtime'] = header .. ',' .. str
                else
                    res.headers['x-spore-runtime'] = str
                end
                return res
            end
end

return m
--
-- Copyright (c) 2010-2015 Francois Perrad
--
-- This library is licensed under the terms of the MIT/X11 license,
-- like Lua itself.
--
