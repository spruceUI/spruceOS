--- Turbo.lua Asynchronous event based Lua Web Framework.
-- It is different from all the other Lua HTTP servers out there in that it's
-- modern, fresh, object oriented and easy to modify.
-- It is written in pure Lua, there are no Lua C modules instead it uses the
-- LuaJIT FFI to do socket and event handling (only applies for Linux).
-- Users of the Tornado web server will recognize the API offered pretty quick.
--
-- If you do not know Lua then do not fear as its probably one of the easiest
-- languages to learn if you know C, Python or Javascript from before.
--
-- Turbo.lua is non-blocking and a features a extremely fast light weight web
-- server. The framework is good for REST APIs, traditional HTTP requests and
-- open connections like Websockets requires beacause of its combination of
-- the raw power of LuaJIT and its event driven nature.
--
-- What sets Turbo.lua apart from the other evented driven servers out there,
-- is that it is the fastest, most scalable and has the smallest footprint of
-- them all. This is thanks to the excellent work done on LuaJIT.
--
-- Please visist https://github.com/kernelsauce/turbo to report issues or ask questions.
--
--
-- Main features and design principles:
--
-- * Simple and intuitive API (much like Tornado)
--
-- * Good documentation
--
-- * No dependencies, except for LuaJIT the Just-In-Time compiler for Lua.
--
-- * Event driven, asynchronous and threadless design
--
-- * Extremely fast with LuaJIT
--
-- * Written completely in pure Lua
--
-- * Linux Epoll support
--
-- * Small footprint
--
--
-- Copyright John Abrahamsen 2011 - 2015
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

local turbo = {}  -- turbo main namespace.

-- The Turbo Web version is of the form A.B.C, where A is the major version,
-- B is the minor version, and C is the micro version. If the micro version
-- is zero, it’s omitted from the version string.
-- When a new release only fixes bugs and doesn’t add new features or
-- functionality, the micro version is incremented. When new features are
-- added in a backwards compatible way, the minor version is incremented and
-- the micro version is set to zero. When there are backwards incompatible
-- changes, the major version is incremented and others are set to zero.
turbo.MAJOR_VERSION = 2
turbo.MINOR_VERSION = 1
turbo.MICRO_VERSION = 3
-- A 3-byte hexadecimal representation of the version, e.g. 0x010201 for
-- version 1.2.1 and 0x010300 for version 1.3.
turbo.VERSION_HEX = 0x020102
if turbo.MICRO_VERSION then
    turbo.VERSION = string.format("%d.%d.%d",
        turbo.MAJOR_VERSION,
        turbo.MINOR_VERSION,
        turbo.MICRO_VERSION)
else
    turbo.VERSION = string.format("%d.%d",
        turbo.MAJOR_VERSION,
        turbo.MINOR_VERSION)
end

if not jit then
    _G.__TURBO_NO_JIT__ = true
end
assert(pcall(require, "ffi"), "No FFI or compatible library available.")
assert(pcall(require, "bit") or pcall(require, "bit32"),
    "No bit or compatible library available")
turbo.platform =        require "turbo.platform"
turbo.log =             require "turbo.log"
if not turbo.platform.__LINUX__ then
    if not pcall(require, "socket") then
        turbo.log.error("Could not load LuaSocket. Aborting.")
    end
    _G.__TURBO_USE_LUASOCKET__ = true
elseif _G.__TURBO_USE_LUASOCKET__ then
    turbo.log.warning(
        "_G.__TURBO_USE_LUASOCKET__ set,"..
        " using LuaSocket (degraded performance).")
end
turbo.ioloop =          require "turbo.ioloop"
turbo.escape =          require "turbo.escape"
turbo.httputil =        require "turbo.httputil"
turbo.tcpserver =       require "turbo.tcpserver"
turbo.httpserver =      require "turbo.httpserver"
turbo.iostream =        require "turbo.iostream"
turbo.iosimple =		require "turbo.iosimple"
turbo.crypto =          require "turbo.crypto"
turbo.async =           require "turbo.async"
turbo.web =             require "turbo.web"
turbo.util =            require "turbo.util"
turbo.coctx =           require "turbo.coctx"
turbo.websocket =       require "turbo.websocket"
turbo.socket =          require "turbo.socket_ffi"
turbo.sockutil =        require "turbo.sockutil"
turbo.hash =            require "turbo.hash"
if turbo.platform.__LINUX__ then
    turbo.inotify =         require "turbo.inotify"
    turbo.fs =              require "turbo.fs"
    turbo.signal =          require "turbo.signal"
    turbo.syscall =         require "turbo.syscall"
    turbo.thread =          require "turbo.thread"
end
turbo.structs =         {}
turbo.structs.deque =   require "turbo.structs.deque"
turbo.structs.buffer =  require "turbo.structs.buffer"

return turbo
