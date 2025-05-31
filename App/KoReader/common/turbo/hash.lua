--- Turbo.lua Hash module
-- Wrappers for OpenSSL crypto.
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

if not _G.TURBO_SSL then
    return setmetatable({},
    {
    __index = function(t, k)
        error("TURBO_SSL is not defined and you are trying to use hash functions.")
    end,
    __call  = function(t, k)
        error("TURBO_SSL is not defined and you are trying to use hash functions.")
    end
    })
end

local ffi = require "ffi"
local buffer = require "turbo.structs.buffer"
require "turbo.cdef"

local lssl = ffi.load(os.getenv("TURBO_LIBSSL") or "ssl")

-- Buffers
local hexstr = buffer()

local hash = {} -- hash namespace
hash.SHA_DIGEST_LENGTH = 20

hash.SHA1 = class("SHA1")

--- Create a SHA1 object. Pass a Lua string with the initializer to digest
-- it.
-- @param str (String)
function hash.SHA1:initialize(str)
    if type(str) == "string" then
        self.md =  ffi.new("unsigned char[?]", hash.SHA_DIGEST_LENGTH)
        lssl.SHA1(str, str:len(), self.md)
        self.final = true
    else
        self.ctx = ffi.new("SHA_CTX")
        assert(lssl.SHA1_Init(self.ctx) == 1, "Could not init SHA_CTX.")
    end
end

--- Update SHA1 context with more data.
-- @param str (String)
function hash.SHA1:update(str)
    assert(self.ctx, "No SHA_CTX in object.")
    assert(not self.final,
           "SHA_CTX already finalized. Please create a new context.")
    assert(lssl.SHA1_Update(self.ctx, str, str:len()) == 1,
           "Could not update SHA_CTX")
end

--- Finalize SHA1 context.
-- @return (char*) Message digest.
function hash.SHA1:finalize()
    if self.final == true then
        return self.md
    end
    self.final = true
    assert(self.ctx, "No SHA_CTX in object.")
    self.md = ffi.new("unsigned char[?]", hash.SHA_DIGEST_LENGTH)
    assert(lssl.SHA1_Final(self.md, self.ctx) == 1, "Could not final SHA_CTX.")
    return self.md
end

--- Keyed-hash message authentication code (HMAC) is a specific construction
-- for calculating a message authentication code (MAC) involving a
-- cryptographic hash function in combination with a secret cryptographic key.
-- @param key (String) Sequence of bytes used as a key.
-- @param digest (String) String to digest.
-- @param raw (Boolean) Indicates whether the output should be a direct binary
--    equivalent of the message digest, or formatted as a hexadecimal string.
-- @return (String) Hex representation of digested string.
function hash.HMAC(key, digest, raw)
    assert(type(key) == "string", "Key is invalid type: "..type(key))
    assert(type(digest) == "string", "Can not hash: "..type(digest))
    local digest =
        lssl.HMAC(lssl.EVP_sha1(),
                  key, key:len(),
                  digest,
                  digest:len(),
                  nil,
                  nil)
    hexstr:clear()
    for i=0, hash.SHA_DIGEST_LENGTH-1 do
        if (raw) then
            hexstr:append_char_right(digest[i])
        else
            hexstr:append_right(string.format("%02x", digest[i]), 2)
        end
    end
    local str = hexstr:__tostring()
    hexstr:clear(true)
    return str
end

--- Compare two SHA1 contexts with the equality operator ==.
-- @return (Boolean) True or false.
function hash.SHA1:__eq(cmp)
    assert(self.final and cmp.final, "Can not compare non final SHA_CTX's")
    assert(self.md and cmp.md, "Missing message digest(s).")
    if ffi.C.memcmp(self.md, cmp.md, hash.SHA_DIGEST_LENGTH) == 0 then
        return true
    else
        return false
    end
end

--- Convert message digest to Lua hex string.
-- @return (String)
function hash.SHA1:hex()
    assert(self.final, "SHA_CTX not final.")
    hexstr:clear()
    for i=0, hash.SHA_DIGEST_LENGTH-1 do
        hexstr:append_right(string.format("%02x", self.md[i]), 2)
    end
    local str = hexstr:__tostring()
    hexstr:clear(true)
    return str
end

return hash
