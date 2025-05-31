--[[--
LuaJIT FFI wrapper for libcrypto (OpenSSL).

@module ffi.crypto
]]

local ffi = require("ffi")
require("ffi/crypto_h")

local libcrypto
if ffi.os == "Windows" then
    libcrypto = ffi.load("libs/libcrypto.dll")
elseif ffi.os == "OSX" then
    libcrypto = ffi.load("libs/libcrypto.1.1.dylib")
else
    libcrypto = ffi.load("libs/libcrypto.so.1.1")
end

local crypto = {}

function crypto.pbkdf2_hmac_sha1(pass, salt, iterations, key_len)
    local buf = ffi.new("char[?]", key_len)
    local res = libcrypto.PKCS5_PBKDF2_HMAC_SHA1(pass, #pass, salt, #salt, iterations, key_len, buf)
    assert(res == 1)
    return ffi.string(buf, key_len)
end

return crypto
