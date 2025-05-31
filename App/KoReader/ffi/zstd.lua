--[[--
LuaJIT FFI wrapper for ZSTD.

@module ffi.zstd
]]

local ffi = require("ffi")
local C = ffi.C

require("ffi/posix_h")
require("ffi/zstd_h")

local zst
if ffi.os == "Windows" then
    zst = ffi.load("libs/libzstd.dll")
elseif ffi.os == "OSX" then
    zst = ffi.load("libs/libzstd.1.dylib")
else
    zst = ffi.load("libs/libzstd.so.1")
end

local zstd = {}

-- c.f., https://github.com/facebook/zstd/tree/dev/examples
function zstd.zstd_compress(ptr, size)
    --print("zstd_compress:", ptr, size)
    local n = zst.ZSTD_compressBound(size)
    local cbuff = C.calloc(n, 1)
    assert(cbuff ~= nil, "Failed to allocate ZSTD compression buffer (" .. tonumber(n) .. " bytes)")
    -- NOTE: We should be quite all right with the default (3), which will most likely trounce zlib's 9 in every respect...
    local clen = zst.ZSTD_compress(cbuff, n, ptr, size, zst.ZSTD_CLEVEL_DEFAULT)
    if zst.ZSTD_isError(clen) ~= 0 then
        C.free(cbuff)
        error(ffi.string(zst.ZSTD_getErrorName(clen)))
    end
    return cbuff, clen
end

function zstd.zstd_uncompress(ptr, size)
    --print("zstd_uncompress:", ptr, size)
    -- The decompressed size is encoded in the ZST frame header
    local n = zst.ZSTD_getFrameContentSize(ptr, size)
    local buff = C.calloc(n, 1)
    assert(buff ~= nil, "Failed to allocate ZSTD decompression buffer (" .. tonumber(n) .. " bytes)")
    local ulen = zst.ZSTD_decompress(buff, n, ptr, size)
    if zst.ZSTD_isError(ulen) ~= 0 then
        C.free(buff)
        error(ffi.string(zst.ZSTD_getErrorName(ulen)))
    end
    return buff, ulen
end

-- Same idea, but with a re-usable decompression context
-- NOTE: We currently don't bother with that for compression,
--       since the only user (BookInfoManager) runs that in a subprocess anyway.

-- More for correctness than anything, make sure the GC will actually free the resources when the variable goes out of scope...
-- NOTE: In Lua 5.1/LuaJIT 2.1, the __gc metamethod is *only* called for userdata, *NOT* tables.
--       There are funky workarounds involving newproxy() available
--       (c.f., https://stackoverflow.com/q/55585619 & https://github.com/LuaJIT/LuaJIT/issues/47),
--       but, for cdata, LuaJIT provides custom finalizer handling, so, do that instead ;).
--       And do it explicitly via ffi.gc, instead of relying on the __gc metamethod of a metatable on a cdata
--       (as bound by via ffi.metatype, c.f., LuaJIT docs and the comments about this in BB.gc @ ffi/blitbuffer.lua).
local DCtx

function zstd.zstd_uncompress_ctx(ptr, size)
    --print("zstd_uncompress_ctx:", ptr, size)

    -- Lazy init the decompression context
    if DCtx == nil then
        DCtx = ffi.gc(zst.ZSTD_createDCtx(), zst.ZSTD_freeDCtx)
        assert(DCtx ~= nil, "Failed to allocate ZSTD decompression context")
    else
        -- Reset the context
        local ret = zst.ZSTD_DCtx_reset(DCtx, zst.ZSTD_reset_session_only)
        assert(zst.ZSTD_isError(ret) == 0, ffi.string(zst.ZSTD_getErrorName(ret)))
    end

    -- The decompressed size is encoded in the ZST frame header
    local n = zst.ZSTD_getFrameContentSize(ptr, size)
    local buff = C.calloc(n, 1)
    assert(buff ~= nil, "Failed to allocate ZSTD decompression buffer (" .. tonumber(n) .. " bytes)")
    local ulen = zst.ZSTD_decompressDCtx(DCtx, buff, n, ptr, size)
    assert(zst.ZSTD_isError(ulen) == 0, ffi.string(zst.ZSTD_getErrorName(ulen)))
    return buff, ulen
end

return zstd
