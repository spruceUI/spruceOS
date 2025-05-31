--
-- lua-Spore : <http://fperrad.github.com/lua-Spore/>
--

local pairs = pairs
require 'Spore'.early_validate = false


local _ENV = nil
local m = {}

function m:call (req)
    local spore = req.env.spore
    local params = spore.params
    local method = spore.method
    local required_params = method.required_params or {}
    local optional_params = method.optional_params or {}
    for k, v in pairs(self) do
        if params[k] == nil then
            local found = false
            for i = 1, #required_params do
                if k == required_params[i] then
                    found = true
                    break
                end
            end
            if not found then
                for i = 1, #optional_params do
                    if k == optional_params[i] then
                        found = true
                        break
                    end
                end
            end
            if found then
                params[k] = v
            end
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
