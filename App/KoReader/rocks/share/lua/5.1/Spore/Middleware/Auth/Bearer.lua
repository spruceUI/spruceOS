--
-- lua-Spore : <http://fperrad.github.com/lua-Spore/>
--


local _ENV = nil
local m = {}

--[[
        The OAuth 2.0 Protocol: Bearer Tokens
--]]

function m:call (req)
    if req.env.spore.authentication and self.bearer_token then
        req.headers['authorization'] = 'Bearer ' .. self.bearer_token
    end
end

return m
--
-- Copyright (c) 2011-2015 Francois Perrad
--
-- This library is licensed under the terms of the MIT/X11 license,
-- like Lua itself.
--
