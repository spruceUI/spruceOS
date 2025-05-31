--
-- lua-Spore : <http://fperrad.github.com/lua-Spore/>
--

local mime = require 'mime'


local _ENV = nil
local m = {}

function m:call (req)
    if req.env.spore.authentication and self.username and self.password then
        req.headers['authorization'] =
            'Basic ' .. mime.b64(self.username .. ':' .. self.password)
    end
end

return m
--
-- Copyright (c) 2010-2015 Francois Perrad
--
-- This library is licensed under the terms of the MIT/X11 license,
-- like Lua itself.
--
