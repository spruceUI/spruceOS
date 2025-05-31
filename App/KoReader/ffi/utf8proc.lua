--[[--
Module for utf8 string operations.

This is a LuaJIT FFI wrapper for utf8proc.

@module ffi.utf8proc
]]

local ffi = require("ffi")
local C = ffi.C

require("ffi/posix_h")
require("ffi/utf8proc_h")

local libutf8proc
if ffi.os == "Windows" then
    libutf8proc = ffi.load("libs/libutf8proc-3.dll")
elseif ffi.os == "OSX" then
    libutf8proc = ffi.load("libs/libutf8proc.3.dylib")
else
    libutf8proc = ffi.load("libs/libutf8proc.so.3")
end

local Utf8Proc = {}

--- Lowercases an utf8-encoded string
--- @string str string to lowercase
--- @bool normalize normalizes the string during operation
--- @treturn string the lowercased string
function Utf8Proc.lowercase(str, normalize)
    if normalize == nil then normalize = true end

    if normalize then
        return Utf8Proc.lowercase_NFKC_Casefold(str)
    else
        return Utf8Proc.cased_dumb(str, true)
    end
end

-- with normalization
function Utf8Proc.lowercase_NFKC_Casefold(str)
    local folded_strz = libutf8proc.utf8proc_NFKC_Casefold(str)
    local folded_str = ffi.string(folded_strz)
    C.free(folded_strz)
    return folded_str
end

-- no normalization here
function Utf8Proc.lowercase_dumb(str)
    return Utf8Proc.cased_dumb(str, true)
end

function Utf8Proc.uppercase_dumb(str)
    return Utf8Proc.cased_dumb(str, false)
end

function Utf8Proc.cased_dumb(str, is_lower)
    local cased = ""
    local tmp_str = (" "):rep(10)
    local tmp_p = ffi.cast("utf8proc_uint8_t *", tmp_str)
    local str_p = ffi.cast("const utf8proc_uint8_t *", str)
    local codepoint = ffi.new("utf8proc_int32_t[1]")
    local count = 0
    local pos = 0
    local str_len = #str -- may contain NUL
    while pos < str_len do
        -- get codepoint
        local bytes = libutf8proc.utf8proc_iterate(str_p + pos, -1, codepoint)
        -- cased codepoint
        local cp = is_lower and libutf8proc.utf8proc_tolower(codepoint[0]) or libutf8proc.utf8proc_toupper(codepoint[0])
        -- encode cased codepoint and get length of new char*
        local len = libutf8proc.utf8proc_encode_char(cp, tmp_p)
        tmp_p[len] = 0
        -- append
        cased = cased .. ffi.string(tmp_p)

        if bytes > 0 then
            count = count + 1
            pos = pos + bytes
        else
            return cased
        end
    end
    return cased
end

--- Normalizes an utf8-encoded string
--- @string str string to lowercase
--- @treturn string the normalized string
function Utf8Proc.normalize_NFC(str)
    local normalized_strz = libutf8proc.utf8proc_NFC(str)
    local normalized_str = ffi.string(normalized_strz)
    C.free(normalized_strz)
    return normalized_str
end

--- Counts codepoints in an utf8-encoded string
--- @string str to count codepoints in
--- @return (int, bool) number of codepoints, operation successfull
function Utf8Proc.count(str)
    local str_p = ffi.cast("const utf8proc_uint8_t *", str)
    local codepoint = ffi.new("utf8proc_int32_t[1]")
    local count = 0
    local pos = 0
    local str_len = #str -- may contain NUL
    while pos < str_len do
        local bytes = libutf8proc.utf8proc_iterate(str_p + pos, -1, codepoint)
        if bytes > 0 then
            count = count + 1
            pos = pos + bytes
        else
            return count, false
        end
    end
    return count, true
end

return Utf8Proc
