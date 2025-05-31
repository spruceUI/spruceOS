--
-- lua-Spore : <http://fperrad.github.com/lua-Spore/>
--

local type = type


local _ENV = nil
local m = {}

function m:call (req)
    req:finalize()
    for i = 1, #self, 2 do
        local cond, func, r = self[i], self[i+1]
        if type(cond) == 'string' then
            r = req.url:match(cond)
        else
            r = cond(req)
        end
        if r then
            return func(req)
        end
    end
end

return m
--
-- Copyright (c) 2010-2015 Francois Perrad
--
-- This library is licensed under the terms of the MIT/X11 license,
-- like Lua itself.
--
