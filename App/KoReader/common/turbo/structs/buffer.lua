-- Turbo.lua Low-level buffer implementation
--
-- Copyright 2013 John Abrahamsen
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

require "turbo.cdef"
require 'turbo.3rdparty.middleclass'
local ffi = require "ffi"

ffi.cdef([[
    struct tbuffer{
        char *data;
        size_t mem;
        size_t sz;
        size_t sz_hint;
    };
]])

--- Low-level Buffer class.
-- Using C buffers. This class supports storing above the LuaJIT memory limit.
-- It is still garbage collected.
local Buffer = class('Buffer')

local function _tbuffer_free(ptr)
    ptr = ffi.cast("struct tbuffer *",  ptr)
    ffi.C.free(ptr.data)
    ffi.C.free(ptr)
end

--- Create a new buffer.
-- @param size_hint The buffer is preallocated with this amount of storage.
-- @return Buffer instance.
function Buffer:initialize(size_hint)
    size_hint = size_hint or 1024
    local ptr = ffi.C.malloc(ffi.sizeof("struct tbuffer"))
    if ptr == nil then
        error("No memory.")
    end
    self.tbuffer = ffi.cast("struct tbuffer *",  ptr)
    ffi.gc(self.tbuffer, _tbuffer_free)
    ptr = ffi.C.malloc(size_hint)
    if ptr == nil then
        error("No memory.")
    end
    self.tbuffer.mem = size_hint
    self.tbuffer.sz = 0
    self.tbuffer.data = ptr
    self.tbuffer.sz_hint = size_hint
end

--- Append data to buffer.
-- @param data The data to append in char * form.
-- @param len The length of the data in bytes.
function Buffer:append_right(data, len)
    if self.tbuffer.mem - self.tbuffer.sz >= len then
        ffi.copy(self.tbuffer.data + self.tbuffer.sz, data, len)
        self.tbuffer.sz = self.tbuffer.sz + len
    else
        -- Realloc and double required memory size.
        local new_sz = self.tbuffer.sz + len
        local new_mem  = new_sz * 2
        local ptr = ffi.C.realloc(self.tbuffer.data, new_mem)
        if ptr == nil then
            error("No memory.")
        end
        self.tbuffer.data = ptr
        ffi.copy(self.tbuffer.data + self.tbuffer.sz, data, len)
        self.tbuffer.mem = new_mem
        self.tbuffer.sz = new_sz
    end
    return self
end

function Buffer:append_char_right(char)
    if self.tbuffer.mem - self.tbuffer.sz >= 1 then
        self.tbuffer.data[self.tbuffer.sz] = char
        self.tbuffer.sz = self.tbuffer.sz + 1
    else
        -- Realloc and double required memory size.
        local new_sz = self.tbuffer.sz + 1
        local new_mem  = new_sz * 2
        local ptr = ffi.C.realloc(self.tbuffer.data, new_mem)
        if ptr == nil then
            error("No memory.")
        end
        self.tbuffer.data = ptr
        self.tbuffer.data[self.tbuffer.sz] = char
        self.tbuffer.mem = new_mem
        self.tbuffer.sz = new_sz
    end
    return self
end

--- Append Lua string to right side of buffer.
-- @param str Lua string
function Buffer:append_luastr_right(str)
    if not str then
        error("Appending a nil value, not possible.")
    end
    self:append_right(str, str:len())
    return self
end

--- Prepend data to buffer.
-- @param data The data to prepend in char * form.
-- @param len The length of the data in bytes.
function Buffer:append_left(data, len)
    if self.tbuffer.mem - self.tbuffer.sz >= len then
        -- Do not use ffi.copy, but memmove as the memory are overlapping.
        if self.tbuffer.sz ~= 0 then
            ffi.C.memmove(
                self.tbuffer.data + len,
                self.tbuffer.data,
                self.tbuffer.sz)
        end
        ffi.copy(self.tbuffer.data, data, len)
        self.tbuffer.sz = self.tbuffer.sz + len
    else
        -- Realloc and double required memory size.
        local new_sz = self.tbuffer.sz + len
        local new_mem  = new_sz * 2
        local ptr = ffi.C.realloc(self.tbuffer.data, new_mem)
        if ptr == nil then
            error("No memory.")
        end
        self.tbuffer.data = ptr
        if self.tbuffer.sz ~= 0 then
            ffi.C.memmove(self.tbuffer.data + len, self.tbuffer.data, self.tbuffer.sz)
        end
        ffi.copy(self.tbuffer.data, data, len)
        self.tbuffer.mem = new_mem
        self.tbuffer.sz = new_sz
    end
    return self
end

--- Prepend Lua string to the buffer
-- @param str Lua string
function Buffer:append_luastr_left(str)
    if not str then
        error("Appending a nil value, not possible.")
    end
    return self:append_left(str, str:len())
end

--- Pop bytes from left side of buffer. If sz exceeds size of buffer then a
-- error is raised. Note: does not release memory allocated.
function Buffer:pop_left(sz)
    if self.tbuffer.sz < sz then
        error("Trying to pop_left side greater than total size of buffer")
    else
        local move = self.tbuffer.sz - sz
        ffi.C.memmove(self.tbuffer.data, self.tbuffer.data + sz, move)
        self.tbuffer.sz = move
    end
    return self
end

--- Pop bytes from right side of the buffer. If sz exceeds size of buffer then
-- a error is raised. Note: does not release memory allocated.
function Buffer:pop_right(sz)
    if self.tbuffer.sz < sz then
        error("Trying to pop_right side greater than total size of buffer")
    else
        self.tbuffer.sz = self.tbuffer.sz - sz
    end
    return self
end

--- Create a "deep" copy of the buffer.
function Buffer:copy()
    local new = Buffer(self.tbuffer.sz)
    new:append_right(self:get())
    return new
end

--- Shrink buffer memory usage to its minimum.
function Buffer:shrink()
    if self.tbuffer.sz_hint > self.tbuffer.sz or
        self.tbuffer.sz == self.tbuffer.mem then
        -- Current size is smaller than size hint or current size equals memory
        -- allocated. Bail.
        return self
    end
    local ptr = ffi.C.realloc(self.tbuffer.data, self.tbuffer.sz)
    if ptr == nil then
        error("No memory.")
    end
    self.tbuffer.data = ptr
    return self
end

--- Clear buffer. Note: does not release memory allocated.
-- @param wipe Zero fill allocated memory range.
function Buffer:clear(wipe)
    if wipe then
        ffi.fill(self.tbuffer.data, self.tbuffer.mem, 0)
    end
    self.tbuffer.sz = 0
    return self
end

--- Get current size of the buffer.
-- @return size of buffer in bytes.
function Buffer:len() return self.tbuffer.sz end

--- Get the total number of bytes currently allocated to this instance.
-- @return number of bytes allocated.
function Buffer:mem() return self.tbuffer.mem end

--- Get internal buffer pointer. Must be treated as a const value.
-- @return char * to data.
-- @return current size of buffer, in bytes.
function Buffer:get() return self.tbuffer.data, self.tbuffer.sz end

--- Convert to Lua type string using the tostring() builtin or implicit
-- conversions.
function Buffer:__tostring()
    return ffi.string(self.tbuffer.data, self.tbuffer.sz)
end

--- Compare two buffers by using the == operator.
function Buffer:__eq(cmp)
    if instanceOf(Buffer, cmp) == true then
        if cmp.tbuffer.sz == self.tbuffer.sz then
            if ffi.C.memcmp(cmp.tbuffer.data,
                self.tbuffer.data,
                self.tbuffer.sz) == 0 then
                return true
            end
        end
    else
        error("Trying to compare Buffer with " .. type(cmp))
    end
    return false
end

--- Concat by using the .. operator, Lua type strings can be concated also.
-- Please note that this involves deep copying and is slower than manually
-- building a buffer with append_right().
function Buffer:__concat(src)
    if type(self) == "string" then
        if instanceOf(Buffer, src) then
            return self .. tostring(src)
        end
    elseif instanceOf(Buffer, self) == true then
        if instanceOf(Buffer, src) == true then
            local new = Buffer(src.tbuffer.sz + self.tbuffer.sz)
            new:append_right(self:get())
            new:append_right(src:get())
            return new
        elseif type(src) == "string" then
            local strlen = src:len()
            local new = Buffer(strlen + self.tbuffer.sz)
            new:append_right(self:get())
            new:append_right(src, strlen)
            return new
        end
    end
    error("Trying to concat Buffer with " .. type(cmp))
end

return Buffer
