--- Turbo.lua Log module
-- A simple log writer implementation with different levels and standard
-- formatting. Messages written is appended to level and timestamp. You
-- can turn off unwanted categories by modifiying the table at log.categories.
--
-- For messages shorter than 4096 bytes a static buffer is used to
-- improve performance. C time.h functions are used as Lua builtin's is
-- not compiled by LuaJIT. This statement applies to all log functions, except
-- log.dump.
--
-- Example output:
-- [S 2013/07/15 18:58:03] [web.lua] 200 OK GET / (127.0.0.1) 0ms
--
-- Copyright John Abrahamsen 2011, 2012, 2013 < JhnAbrhmsn@gmail.com >
--
-- "Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE."

local util = require "turbo.util"
local platform = require "turbo.platform"
local ffi = require "ffi"

local log = {
    ["categories"] = {
        -- Enable or disable global log categories.
        -- The categories can be modified at any time.
        ["success"] = true,
        ["notice"] = true,
        ["warning"] = true,
        ["error"] = true,
        ["debug"] = true,
        ["development"] = true,
        ["stacktrace"] = true
    }
} -- log namespace.

local buf = ffi.new("char[4096]") -- Buffer for log lines.
local time_t = ffi.new("time_t[1]")


--- Disable all login features.
function log.disable_all()
    log.categories = {
        ["success"] = false,
        ["notice"] = false,
        ["warning"] = false,
        ["error"] = false,
        ["debug"] = false,
        ["development"] = false
    }
end

if platform.__UNIX__ then
    --- Log to stdout. Success category.
    -- Use for successfull events etc.
    -- @note Messages are printed with green color.
    -- @param str (String) Message to output.
    function log.success(str)
        if log.categories.success == false then
            return
        end
        ffi.C.time(time_t)
        local tm = ffi.C.localtime(time_t)
        local sz = ffi.C.strftime(buf, 4096, "\x1b[32m[S %Y/%m/%d %H:%M:%S] ", tm)
        local offset
        if sz + str:len() < 4094 then
            -- Use static buffer.
            ffi.C.sprintf(buf + sz, "%s\x1b[0m\n", ffi.cast("const char*", str))
            ffi.C.fputs(buf, io.stdout)
        else
            -- Use Lua string.
            io.stdout:write(ffi.string(buf, sz) .. str .. "\x1b[0m\n")
        end
    end
else
    function log.success(str)
        if log.categories.warning == false then
            return
        end
        io.stdout:write(
            string.format("%s %s \r\n",
                os.date("[S %Y/%m/%d %H:%M:%S]", os.time()),
                str))
    end
end

if platform.__UNIX__ then
    --- Log to stdout. Notice category.
    -- Use for notices, typically non-critical messages to give a hint.
    -- @note Messages are printed with white color.
    -- @param str (String) Message to output.
    function log.notice(str)
        if log.categories.notice == false then
            return
        end
        ffi.C.time(time_t)
        local tm = ffi.C.localtime(time_t)
        local sz = ffi.C.strftime(buf, 4096, "[I %Y/%m/%d %H:%M:%S] ", tm)
        local offset
        if sz + str:len() < 4094 then
            -- Use static buffer.
            ffi.C.sprintf(buf + sz, "%s\n", ffi.cast("const char*", str))
            ffi.C.fputs(buf, io.stdout)
        else
            -- Use Lua string.
            io.stdout:write(ffi.string(buf, sz) .. str .. "\n")
        end
    end
else
    function log.notice(str)
        if log.categories.warning == false then
            return
        end
        io.stdout:write(
            string.format("%s %s \r\n",
                os.date("[I %Y/%m/%d %H:%M:%S]", os.time()),
                str))
    end
end

--- Log to stderr. Warning category.
-- Use for warnings.
-- @note Messages are printed with yellow color.
-- @param str (String) Message to output.
if platform.__UNIX__ then
    function log.warning(str)
        if log.categories.warning == false then
            return
        end
        ffi.C.time(time_t)
        local tm = ffi.C.localtime(time_t)
        local sz = ffi.C.strftime(
            buf,
            4096,
            "\x1b[33m[W %Y/%m/%d %H:%M:%S] ",
            tm)
        local offset
        if sz + str:len() < 4094 then
            -- Use static buffer.
            ffi.C.sprintf(buf + sz, "%s\x1b[0m\n", ffi.cast("const char*", str))
            ffi.C.fputs(buf, io.stderr)
        else
            -- Use Lua string.
            io.stdout:write(ffi.string(buf, sz) .. str .. "\x1b[0m\n")
        end
    end
else
    function log.warning(str)
        if log.categories.warning == false then
            return
        end
        io.stdout:write(
            string.format("%s %s \r\n",
                os.date("[W %Y/%m/%d %H:%M:%S]", os.time()),
                str))
    end
end

--- Log to stderr. Error category.
-- Use for critical errors, when something is clearly wrong.
-- @note Messages are printed with red color.
-- @param str (String) Message to output.
if platform.__UNIX__ then
    function log.error(str)
        if log.categories.error == false then
            return
        end
        ffi.C.time(time_t)
        local tm = ffi.C.localtime(time_t)
        local sz = ffi.C.strftime(buf, 4096, "\x1b[31m[E %Y/%m/%d %H:%M:%S] ", tm)
        local offset
        if sz + str:len() < 4094 then
            -- Use static buffer.
            ffi.C.sprintf(buf + sz, "%s\x1b[0m\n", ffi.cast("const char*", str))
            ffi.C.fputs(buf, io.stderr)
        else
            -- Use Lua string.
            io.stdout:write(ffi.string(buf, sz) .. str .. "\x1b[0m\n")
        end
    end
else
    function log.error(str)
        if log.categories.warning == false then
            return
        end
        io.stdout:write(
            string.format("%s %s \r\n",
                os.date("[E %Y/%m/%d %H:%M:%S]", os.time()),
                str))
    end
end

if platform.__UNIX__ then
    --- Log to stdout. Debug category.
    -- Use for debug messages not critical for releases.
    -- @note Messages are printed with white color.
    -- @param str (String) Message to output.
    function log.debug(str)
        if log.categories.debug == false then
            return
        end
        ffi.C.time(time_t)
        local tm = ffi.C.localtime(time_t)
        local sz = ffi.C.strftime(buf, 4096, "[D %Y/%m/%d %H:%M:%S] ", tm)
        local offset
        if sz + str:len() < 4094 then
            -- Use static buffer.
            ffi.C.sprintf(buf + sz, "%s\n", ffi.cast("const char*", str))
            ffi.C.fputs(buf, io.stdout)
        else
            -- Use Lua string.
            io.stdout:write(ffi.string(buf, sz) .. str .. "\n")
        end
    end
else
    function log.debug(str)
        if log.categories.warning == false then
            return
        end
        io.stdout:write(
            string.format("%s %s \r\n",
                os.date("[D %Y/%m/%d %H:%M:%S]", os.time()),
                str))
    end
end

if platform.__UNIX__ then
    --- Log to stdout. Development category.
    -- Use for development purpose messages.
    -- @note Messages are printed with cyan color.
    -- @param str (String) Message to output.
    function log.devel(str)
        if log.categories.development == false then
            return
        end
        ffi.C.time(time_t)
        local tm = ffi.C.localtime(time_t)
        local sz = ffi.C.strftime(buf, 4096, "\x1b[36m[d %Y/%m/%d %H:%M:%S] ", tm)
        local offset
        if sz + str:len() < 4094 then
            -- Use static buffer.
            ffi.C.sprintf(buf + sz, "%s\x1b[0m\n", ffi.cast("const char*", str))
            ffi.C.fputs(buf, io.stdout)
        else
            -- Use Lua string.
            io.stdout:write(ffi.string(buf, sz) .. str .. "\x1b[0m\n")
        end
    end
else
    function log.devel(str)
        if log.categories.warning == false then
            return
        end
        io.stdout:write(
            string.format("%s %s \r\n",
                os.date("[d %Y/%m/%d %H:%M:%S]", os.time()),
                str))
    end
end

--- Stringify Lua table.
function log.stringify(t, name, indent)
    local cart     -- a container
    local autoref  -- for self references
    local function isemptytable(t) return next(t) == nil end
    local function basicSerialize (o)
        local so = tostring(o)
        if type(o) == "function" then
            local info = debug.getinfo(o, "S")
            -- info.name is nil because o is not a calling level
            if info.what == "C" then
                return string.format("%q", so .. ", C function")
            else
                -- the information is defined through lines
                return string.format("%q", so .. ", defined in (" ..
                    info.linedefined .. "-" .. info.lastlinedefined ..
                    ")" .. info.source)
            end
        elseif type(o) == "number" or type(o) == "boolean" then
            return so
        else
            return string.format("%q", so)
        end
    end
    local function addtocart (value, name, indent, saved, field)
        indent = indent or ""
        saved = saved or {}
        field = field or name
        cart = cart .. indent .. field
        if type(value) ~= "table" then
            cart = cart .. " = " .. basicSerialize(value) .. ";\n"
        else
            if saved[value] then
                cart = cart .. " = {}; -- " .. saved[value]
                    .. " (self reference)\n"
                autoref = autoref ..  name .. " = " .. saved[value] .. ";\n"
            else
                saved[value] = name
                --if tablecount(value) == 0 then
                if isemptytable(value) then
                    cart = cart .. " = {};\n"
                else
                    cart = cart .. " = {\n"
                    for k, v in pairs(value) do
                        k = basicSerialize(k)
                        local fname = string.format("%s[%s]", name, k)
                        field = string.format("[%s]", k)
                        -- three spaces between levels
                        addtocart(v, fname, indent .. "   ", saved, field)
                    end
                    cart = cart .. indent .. "};\n"
                end
            end
        end
    end
    name = name or "__unnamed__"
    if type(t) ~= "table" then
        return name .. " = " .. basicSerialize(t)
    end
    cart, autoref = "", ""
    addtocart(t, name, indent)
    return cart .. autoref
end

--- Usefull pretty printer for debug purposes.
-- @param stuff Value to print. All supported.
-- @param description (String) Optional description of the value dumped.
function log.dump(stuff, description)
    io.stdout:write(log.stringify(stuff, description) .. "\n")
end

--- Log stacktrace to stderr.
-- Use for warnings.
-- @note Messages are printed with white color.
-- @param str (String) Message to output.
function log.stacktrace(str)
    if log.categories.stacktrace == false then
        return
    end
    io.stderr:write(str .. "\n")
end

return log
