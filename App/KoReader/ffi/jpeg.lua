--[[--
Module for JPEG decoding/encoding.

This is a LuaJIT FFI wrapper for turbojpeg.

@module ffi.jpeg
]]

local ffi = require("ffi")
local C = ffi.C
local BB = require("ffi/blitbuffer")

require("ffi/posix_h")
require("ffi/turbojpeg_h")

local turbojpeg
if ffi.os == "Windows" then
    turbojpeg = ffi.load("libs/libturbojpeg.dll")
elseif ffi.os == "OSX" then
    turbojpeg = ffi.load("libs/libturbojpeg.dylib")
else
    turbojpeg = ffi.load("libs/libturbojpeg.so")
end

local Jpeg = {}

function Jpeg.openDocument(filename, color)
    local fh = io.open(filename, "rb")
    assert(fh, "couldn't open JPG file")
    local data = fh:read("*a")
    fh:close()

    return Jpeg.openDocumentFromMem(data, color)
end

function Jpeg.openDocumentFromMem(data, color)
    local handle = turbojpeg.tj3Init(turbojpeg.TJINIT_DECOMPRESS)
    assert(handle, "no TurboJPEG API decompressor handle")
    -- Gotta go fast!
    turbojpeg.tj3Set(handle, turbojpeg.TJPARAM_FASTUPSAMPLE, 1)
    turbojpeg.tj3Set(handle, turbojpeg.TJPARAM_FASTDCT, 1)

    if turbojpeg.tj3DecompressHeader(handle, ffi.cast("const unsigned char*", data), #data) < 0 then
        turbojpeg.tj3Destroy(handle)
        error("reading JPEG header")
    end

    local width = turbojpeg.tj3Get(handle, turbojpeg.TJPARAM_JPEGWIDTH)
    local height = turbojpeg.tj3Get(handle, turbojpeg.TJPARAM_JPEGHEIGHT)
    --[[
    local inSubsamp = turbojpeg.tj3Get(handle, turbojpeg.TJPARAM_SUBSAMP)
    local inColorspace = turbojpeg.tj3Get(handle, turbojpeg.TJPARAM_COLORSPACE)
    --]]

    local image_bb
    local format
    local components
    if color then
        image_bb = BB.new(width, height, BB.TYPE_BBRGB24)
        components = 3
        format = turbojpeg.TJPF_RGB
    else
        image_bb = BB.new(width, height, BB.TYPE_BB8)
        components = 1
        format = turbojpeg.TJPF_GRAY
    end

    if turbojpeg.tj3Decompress8(handle, ffi.cast("unsigned char*", data), #data,
                                ffi.cast("unsigned char*", image_bb.data), image_bb.stride, format) < 0 then
        turbojpeg.tj3Destroy(handle)
        error("decoding JPEG file")
    end

    turbojpeg.tj3Destroy(handle)
    return image_bb, width, height, components
end

function Jpeg.encodeToFile(filename, source_ptr, w, stride, h, quality, color_type, subsample)
    local handle = turbojpeg.tj3Init(turbojpeg.TJINIT_COMPRESS)
    assert(handle, "no TurboJPEG API compressor handle")

    turbojpeg.tj3Set(handle, turbojpeg.TJPARAM_SUBSAMP, subsample or turbojpeg.TJSAMP_420)
    turbojpeg.tj3Set(handle, turbojpeg.TJPARAM_QUALITY, quality or 75)
    turbojpeg.tj3Set(handle, turbojpeg.TJPARAM_FASTDCT, 1)

    local jpeg_size = ffi.new("size_t [1]")
    local jpeg_image = ffi.new("unsigned char* [1]")

    if turbojpeg.tj3Compress8(handle, source_ptr, w, stride, h, color_type or turbojpeg.TJPF_RGB, jpeg_image, jpeg_size) == 0 then
        local fhandle = C.open(filename, bit.bor(C.O_WRONLY, C.O_CREAT, C.O_TRUNC, C.O_CLOEXEC), ffi.cast("int", bit.bor(C.S_IRUSR, C.S_IWUSR, C.S_IRGRP, C.S_IROTH)))
        if fhandle >= 0 then
            C.write(fhandle, jpeg_image[0], jpeg_size[0])
            C.close(fhandle)
        end
    end

    turbojpeg.tj3Destroy(handle)
    -- Handles NULL pointers sanely
    turbojpeg.tj3Free(jpeg_image[0])
end

-- convert rgb to grayscale
-- gray = 0.299 R + 0.587 G + 0.114 B
-- https://www.dynamsoft.com/blog/insights/image-processing/image-processing-101-color-space-conversion/
function Jpeg.convertToGray(source_ptr, stride, h)
    for y = 0, h - 1 do
        local offs = y * stride
        local offs_8bit = offs
        for _ = 0, tonumber(stride), 3 do
            local r = .299 * source_ptr[offs]
            offs = offs + 1
            local g = .587 * source_ptr[offs]
            offs = offs + 1
            local b = .114 * source_ptr[offs]
            offs = offs + 1
            source_ptr[offs_8bit] = math.floor(r + g + b + 0.5)
            offs_8bit = offs_8bit + 1
        end
    end
end

function Jpeg.writeBMP(filename, source_ptr, w, stride, h, grayscale)
    local handle = turbojpeg.tj3Init(turbojpeg.TJINIT_COMPRESS)
    assert(handle, "no TurboJPEG API compressor handle")

    local pixel_format
    if grayscale then
        pixel_format = turbojpeg.TJPF_GRAY
        Jpeg.convertToGray(source_ptr, stride, h)
    else
        pixel_format = turbojpeg.TJPF_RGB
    end

    -- if file extension is not ".bmp" tjSaveImage uses netpbm format!
    if filename:sub(-#".bmp") == ".bmp" then
        turbojpeg.tj3SaveImage8(handle, filename, source_ptr, w, stride, h, pixel_format)
    else
        os.remove(filename)
        local tmp_filename = filename .. ".tmp.bmp"
        turbojpeg.tj3SaveImage8(handle, tmp_filename, source_ptr, w, stride, h, pixel_format)
        os.rename(tmp_filename, filename)
    end

    turbojpeg.tj3Destroy(handle)
end

return Jpeg
