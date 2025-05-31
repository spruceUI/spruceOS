--- Turbo Web Cryto module
-- C defs for LuaJIT FFI and wrappers.
--
-- Copyright 2011, 2012, 2013 John Abrahamsen
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local ffi = require "ffi"
local platform = require "turbo.platform"
require "turbo.cdef"

if not _G.TURBO_SSL then
    return setmetatable({},
    {
    __index = function(t, k)
        error("TURBO_SSL is not defined and you are trying to use SSL.")
    end,
    __call  = function(t, k)
        error("TURBO_SSL is not defined and you are trying to use SSL.")
    end
    })
elseif platform.__LINUX__ and not _G.__TURBO_USE_LUASOCKET__ then
    return require "turbo.crypto_linux"
else
    return require "turbo.crypto_luasec"
end
