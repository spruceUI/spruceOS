-- Turbo.lua Utilities module.
--
-- Copyright 2011, 2012, 2013, 2014 John Abrahamsen
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

local ffi =         require "ffi"
local buffer =      require "turbo.structs.buffer"
local platform =    require "turbo.platform"
local luasocket
if not platform.__LINUX__ or _G.__TURBO_USE_LUASOCKET__ then
    luasocket = require "socket"
end
require "turbo.cdef"
local C = ffi.C

local g_time_str_buf, g_time_t, g_timeval
if platform.__LINUX__ and not _G.__TURBO_USE_LUASOCKET__ then
    g_time_str_buf = ffi.new("char[1024]")
    g_time_t = ffi.new("time_t[1]")
    g_timeval = ffi.new("struct timeval")
end

local util = {}


--- Split string into table.
function util.strsplit(str, sep, max, pattern)
    assert(sep ~= '', "Separator is not a string or a empty string.")
    assert(max == nil or max >= 1, "Max is 0 or a negative number.")

    local record = {}
    if str:len() > 0 then
        local plain = not pattern
        max = max or -1
        local field, start = 1, 1
        local first, last = str:find(sep, start, plain)
        while first and max ~= 0 do
            record[field] = str:sub(start, first-1)
            field = field+1
            start = last+1
            first, last = str:find(sep, start, plain)
            max = max-1
        end
        record[field] = str:sub(start)
    end
    return record
end

-- Strip white space from sides of a string
function util.strstrip(str)
    return str:match("^%s*(.-)%s*$")
end

--- Create substring from.
-- Beware that index starts at 0.
-- @param from From index, can be nil to indicate start.
-- @param to To index, can be nil to indicate end.
-- @return string
function util.strsubstr(str, from, to)
    local len = str:len()
    from = from or 0
    to = to or len
    assert(from < len, "From out of range.")
    assert(to <= len, "To out of range.")
    assert(from < to, "From greater than to.")
    local ptr = ffi.cast("char *", str)
    return ffi.string(ptr + from, to - from)
end

--- Create a random string.
function util.rand_str(len)
    math.randomseed(util.gettimeofday()+math.random(0x0,0xffffffff))
    len = len or 64
    local bytes = buffer(len)
    for i = 1, len do
        bytes:append_char_right(ffi.cast("char", math.random(0x0, 0x80)))
    end
    bytes = tostring(bytes)
    return bytes
end


--*************** Table utilites ***************

--- Merge two tables to one.
function util.tablemerge(t1, t2)
    for k, v in pairs(t2) do
        if (type(v) == "table") and (type(t1[k] or false) == "table") then
            util.tablemerge(t1[k], t2[k])
        else
            t1[k] = v
        end
    end
    return t1
end

--- Join a list into a string with  given delimiter.
function util.join(delimiter, list)
    local len = #list
    if len == 0 then
        return ""
    end
    local string = list[1]
    for i = 2, len do
        string = string .. delimiter .. list[i]
    end
    return string
end

--- Returns true if value exists in table.
function util.is_in(needle, haystack)
    if not needle or not haystack then
        return nil
    end
    local i
    for i = 1, #haystack, 1 do
        if needle == haystack[i] then
            return true
        end
    end
    return
end

--- unpack that does not cause trace abort.
-- May not be very fast if large tables are unpacked.
function util.funpack(t, i)
    i = i or 1
    if t[i] ~= nil then
        return t[i], util.funpack(t, i + 1)
    end
end


--*************** Time and date ***************

--- Current msecs since epoch. Better granularity than Lua builtin.
-- @return Number
if platform.__LINUX__ and not _G.__TURBO_USE_LUASOCKET__ then
    function util.gettimeofday()
        C.gettimeofday(g_timeval, nil)
        return (tonumber((g_timeval.tv_sec * 1000)+
                         (g_timeval.tv_usec / 1000)))
    end
else
    function util.gettimeofday()
        return math.ceil(luasocket.gettime() * 1000)
    end
end
do
    local rt_support, rt = pcall(ffi.load, "rt")
    if not rt_support or _G.__TURBO_USE_LUASOCKET__ then
        util.gettimemonotonic = util.gettimeofday
    else
        local ts = ffi.new("struct timespec")
        -- Current msecs since arbitrary start point, doesn't jump due to
        -- time changes
        -- @return Number
        function util.gettimemonotonic()
            rt.clock_gettime(rt.CLOCK_MONOTONIC, ts)
            return (tonumber((ts.tv_sec*1000)+(ts.tv_nsec/1000000)))
        end
    end
end

--- Create a time string used in HTTP cookies.
-- "Sun, 04-Sep-2033 16:49:21 GMT"
if platform.__LINUX__ and not _G.__TURBO_USE_LUASOCKET__ then
    function util.time_format_cookie(epoch)
        g_time_t[0] = epoch
        local tm = C.gmtime(g_time_t)
        local sz = C.strftime(
            g_time_str_buf,
            1024,
            "%a, %d-%b-%Y %H:%M:%S GMT",
            tm)
        return ffi.string(g_time_str_buf, sz)
    end
else
    function util.time_format_cookie(time)
        return os.date(
            "%a, %d-%b-%Y %H:%M:%S GMT",
            time)
    end
end

if platform.__LINUX__ and not _G.__TURBO_USE_LUASOCKET__ then
    --- Create a time string used in HTTP header fields.
    -- "Sun, 04 Sep 2033 16:49:21 GMT"
    function util.time_format_http_header(time_t)
        g_time_t[0] = time_t / 1000
        local tm = C.gmtime(g_time_t)
        local sz = C.strftime(
            g_time_str_buf,
            1024,
            "%a, %d %b %Y %H:%M:%S GMT",
            tm)
        return ffi.string(g_time_str_buf, sz)
    end
else
    function util.time_format_http_header(time)
        return os.date(
            "%a, %d %b %Y %H:%M:%S GMT",
            time / 1000)
    end
end

--*************** File ***************

--- Check if file exists on local filesystem.
-- @param path Full path to file
-- @return True or false.
function util.file_exists(path)
    local f = io.open(path, "r")
    if f ~= nil then
        io.close(f)
        return true
    else
        return false
    end
end

function util.read_all(file)
    local f = io.open(file, "rb")
    assert(f, "Could not open file " .. file .. " for reading.")
    local content = f:read("*all")
    f:close()
    return content
end


--******** Low-level buffer search *********

-- Fast string case agnostic comparison
function util.strcasecmp(str1, str2)
    return tonumber(ffi.C.strcasecmp(str1, str2))
end

--- Find substring in memory string.
-- Based on lj_str_find in lj_str.c in LuaJIT by Mike Pall.
function util.str_find(s, p, slen, plen)
    if plen <= slen then
        if plen == 0 then
            return s
        else
            local c = ffi.cast("int", p[0])
            p = p + 1
            plen = plen - 1
            slen = slen - plen
            local q
            while slen > 0 do
                q = ffi.cast("char*", C.memchr(s, c, slen))
                if q == nil then
                    break
                end
                if C.memcmp(q + 1, p, plen) == 0 then
                    return q
                end
                q = q + 1
                slen = slen - (q - s)
                s = q
            end
        end
    end
end

--- Turbo Booyer-Moore memory search algorithm.
-- DEPRECATED as of v.1.1.
-- @param x char* Needle memory pointer
-- @param m int Needle size
-- @param y char* Haystack memory pointer
-- @param n int Haystack size.
function util.TBM(x, m, y, n)
    log.warning("turbo.util.TBM is deprecated.")
    return util.str_find(y, x, n, m)
end

--- Convert number value to hexadecimal string format.
-- @param num The number to convert.
-- @return String
function util.hex(num)
    local hexstr = '0123456789abcdef'
    local s = ''
    while num > 0 do
        local mod = math.fmod(num, 16)
        s = string.sub(hexstr, mod+1, mod+1) .. s
        num = math.floor(num / 16)
    end
    if s == '' then
        s = '0'
    end
    return s
end
local hex = util.hex

--- Dump memory region to stdout, from ptr to given size. Usefull for
-- debugging Luajit FFI. Notice! This can and will cause a SIGSEGV if
-- not being used on valid pointers.
-- @param ptr A cdata pointer (from FFI)
-- @param sz (Number) Length to dump contents for.
function util.mem_dump(ptr, sz)
    local voidptr = ffi.cast("unsigned char *", ptr)
    if not voidptr then
        error("Trying to dump null ptr")
    end

    io.write(string.format("Pointer type: %s\
        From memory location: 0x%s dumping %d bytes\n",
        ffi.typeof(ptr),
        hex(tonumber(ffi.cast("intptr_t", voidptr))),
        sz))
    local p = 0;
    local sz_base_1 = sz - 1
    for i = 0, sz_base_1 do
        if (p == 10) then
            p = 0
            io.write("\n")
        end
        local hex_string
        if (voidptr[i] < 0xf) then
            hex_string = string.format("0x0%s ", hex(voidptr[i]))
        else
            hex_string = string.format("0x%s ", hex(voidptr[i]))
        end
        io.write(hex_string)
        p = p + 1
    end
    io.write("\n")
end

--- Loads dynamic library with helper functions or bails out with error.
-- @param name Custom library name or path
function util.load_libtffi(name)
    local have_name = name and true or false
    name = name or os.getenv("TURBO_LIBTFFI") or "libtffi_wrap"
    local ok, lib = pcall(ffi.load, name)
    if not ok then
        -- Try the old loading method which works for some Linux distros.
        -- But only if name is not given as argument.
        if not have_name then
            ok, lib = pcall(ffi.load, "/usr/local/lib/libtffi_wrap.so")
        end
        if not ok then
            ok, lib = pcall(ffi.load, "common/libtffi_wrap.so")
        end
        if not ok then
            -- Still not OK...
            error("Could not load " .. name .. " \
            Please run makefile and ensure that installation is done correct.")
        end
    end
    return lib
end

return util
