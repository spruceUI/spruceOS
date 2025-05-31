--
-- lua-Spore : <http://fperrad.github.com/lua-Spore/>
--

local pairs = pairs
require 'Spore'.early_validate = false


local _ENV = nil
local m = {}

function m:call (req)
    local params = req.env.spore.params
    for k, v in pairs(self) do
        params[k] = v
    end
end

return m
--
-- Copyright (c) 2010-2015 Francois Perrad
--
-- This library is licensed under the terms of the MIT/X11 license,
-- like Lua itself.
--
