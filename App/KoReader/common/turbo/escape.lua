--- Turbo.lua Escape module
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

local json = require('turbo.3rdparty.JSON')

local escape = {} -- escape namespace

--- JSON stringify a table.
-- @param t Value to JSON encode.
-- @note May raise a error if table could not be decoded.
function escape.json_encode(t)
    return json:encode(t)
end

--- Decode a JSON string to table.
-- @param s (String) JSON enoded string to decode into
-- Lua primitives.
-- @return (Table)
function escape.json_decode(s)
    return json:decode(s)
end

local function _unhex(hex) return string.char(tonumber(hex, 16)) end
--- Unescape a escaped hexadecimal representation string.
-- @param s (String) String to unescape.
function escape.unescape(s)
    return string.gsub(s, "%%(%x%x)", _unhex)
end

local function _hex(c)
    return string.format("%%%02x", string.byte(c))
end
--- Encodes a string into its escaped hexadecimal representation.
-- @param s (String) String to escape.
function escape.escape(s)
    return string.gsub(s, "([^A-Za-z0-9_])", _hex)
end

--- Encodes the HTML entities in a string. Helpfull to avoid XSS.
-- @param s (String) String to escape.
function escape.html_escape(s)
    assert("Expected string in argument #1.")
    return (string.gsub(s, "[}{\">/<'&]", {
        ["&"] = "&amp;",
        ["<"] = "&lt;",
        [">"] = "&gt;",
        ['"'] = "&quot;",
        ["'"] = "&#39;",
        ["/"] = "&#47;"
    }))
end

-- Remove trailing and leading whitespace from string.
-- @param s String
function escape.trim(s)
    -- from PiL2 20.4
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- Remove leading whitespace from string.
-- @param s String
function escape.ltrim(s)
    return (s:gsub("^%s*", ""))
end

-- Remove trailing whitespace from string.
-- @param s String
function escape.rtrim(s)
    local n = #s
    while n > 0 and s:find("^%s", n) do n = n - 1 end
    return s:sub(1, n)
end

----- Very Fast MIME BASE64 Encoding / Decoding Routines
--------------- authored by Jeff Solinsky
do
    local ffi = require'ffi'
    local bit = jit and require "bit" or require "bit32"
    local rshift = bit.rshift
    local lshift = bit.lshift
    local bor = bit.bor
    local band = bit.band
    local floor = math.floor

    local mime64chars = ffi.new("uint8_t[64]",
     "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
    local mime64lookup = ffi.new("uint8_t[256]")
    ffi.fill(mime64lookup, 256, 0xFF)
    for i=0,63 do
        mime64lookup[mime64chars[i]]=i
    end

    local u8arr= ffi.typeof'uint8_t[?]'
    local u8ptr=ffi.typeof'uint8_t*'

    --- Base64 decode a string or a FFI char *.
    -- @param str (String or char*) Bytearray to decode.
    -- @param sz (Number) Length of string to decode, optional if str is a Lua string
    -- @return (String) Decoded string.
    function escape.base64_decode(str, sz)
        if (type(str)=="string") and (sz == nil) then sz=#str end
        local m64, b1 -- value 0 to 63, partial byte
        local bin_arr=ffi.new(u8arr, floor(bit.rshift(sz*3,2)))
        local mptr = ffi.cast(u8ptr,bin_arr) -- position in binary mime64 output array
        local bptr = ffi.cast(u8ptr,str)
        local i = 0
        while true do
            repeat
                if i >= sz then goto done end
                m64 = mime64lookup[bptr[i]]
                i=i+1
            until m64 ~= 0xFF -- skip non-mime characters like newlines
            b1=lshift(m64, 2)
            repeat
                if i >= sz then goto done end
                m64 = mime64lookup[bptr[i]]
                i=i+1
            until m64 ~= 0xFF -- skip non-mime characters like newlines
            mptr[0] = bor(b1,rshift(m64, 4)); mptr=mptr+1
            b1 = lshift(m64,4)
            repeat
                if i >= sz then goto done end
                m64 = mime64lookup[bptr[i]]
                i=i+1
            until m64 ~= 0xFF -- skip non-mime characters like newlines
            mptr[0] = bor(b1,rshift(m64, 2)); mptr=mptr+1
            b1 = lshift(m64,6)
            repeat
                if i >= sz then goto done end
                m64 = mime64lookup[bptr[i]]
                i=i+1
            until m64 ~= 0xFF -- skip non-mime characters like newlines
            mptr[0] = bor(b1, m64); mptr=mptr+1
        end
    ::done::
        return ffi.string(bin_arr, (mptr-bin_arr))
    end


    local mime64shorts=ffi.new('uint16_t[4096]')
    for i=0,63 do
        for j=0,63 do
            local v
            if ffi.abi("le") then
                v=mime64chars[j]*256+mime64chars[i]
            else
                v=mime64chars[i]*256+mime64chars[j]
            end
            mime64shorts[i*64+j]=v
        end
    end

    local u16arr = ffi.typeof"uint16_t[?]"
    local crlf16 = ffi.new("uint16_t[1]")
    if ffi.abi("le") then
        crlf16[0] = (0x0A*256)+0x0D
    else
        crlf16[0] = (0x0D*256)+0x0A
    end
    local eq=string.byte('=')
    --- Base64 encode binary data of a string or a FFI char *.
    -- @param str (String or char*) Bytearray to encode.
    -- @param sz (Number) Length of string to encode, optional if str is a Lua string
    -- @param disable_break (Bool) Do not break result with newlines, optional
    -- @return (String) Encoded base64 string.
    function escape.base64_encode(str, sz, disable_break)
        if (type(str)=="string") and (sz == nil) then sz=#str end
        local outlen = floor(sz*2/3)
        outlen = outlen + floor(outlen/19)+3
        local m64arr=ffi.new(u16arr,outlen)
        local l,p,v=0,0
        local bptr = ffi.cast(u8ptr,str)
        local c = disable_break and -1 or 38 -- put a new line after every 76 characters
        local i,k=0,0
        ::while_3bytes::
            if i+3>sz then goto break3 end
            v=bor(lshift(bptr[i],16),lshift(bptr[i+1],8),bptr[i+2])
            i=i+3
            ::encode_last3::
            if c==k then
                m64arr[k]=crlf16[0]
                k=k+1
                c=k+38 -- 76 /2 = 38
            end
            m64arr[k]=mime64shorts[rshift(v,12)]
            m64arr[k+1]=mime64shorts[band(v,4095)]
            k=k+2
            goto while_3bytes
        ::break3::
        if l>0 then
            -- Add trailing equal sign padding
            if l==1 then
                -- 1 byte encoded needs two trailing equal signs
                m64arr[k-1]=bor(lshift(eq,8),eq)
            else
                -- 2 bytes encoded needs one trailing equal sign
                (ffi.cast(u8ptr,m64arr))[lshift(k,1)-1]=eq
            end
        else
            l=sz-i -- get remaining len (1 or 2 bytes)
            if l>0 then
                v=lshift(bptr[i],16)
                if l==2 then v=bor(v,lshift(bptr[i+1],8)) end
                goto encode_last3
            end
        end
        return ffi.string(m64arr,lshift(k,1))
    end
end

return escape
