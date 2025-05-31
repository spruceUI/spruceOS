--- Turbo.lua C Platform / OS variables.
--
-- Copyright 2014 John Abrahamsen
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

local uname = ""
if not ffi.abi("win") then
    uname = (function()
        local f = io.popen("uname")
        local l = f:read("*a")
        f:close()
        return l
    end)()
end

return {
    __WINDOWS__ = ffi.abi("win"),
    __UNIX__ = uname:match("Unix") or uname:match("Linux") or 
        uname:match("Darwin") and true or false,
    __LINUX__ = uname:match("Linux") and true or false,
    __DARWIN__ = uname:match("Darwin") and true or false,
    __ABI32__ = ffi.abi("32bit"),
    __ABI64__ = ffi.abi("64bit"),
    __X86__ = ffi.arch == "x86",
    __X64__ = ffi.arch == "x64",
    __PPC__ = ffi.arch == "ppc",
    __PPC64__ = ffi.arch == "ppc64le",
    __ARM__ = ffi.arch == "arm",
    __MIPSEL__ = ffi.arch == "mipsel",
}
