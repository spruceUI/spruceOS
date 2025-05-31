--[[--
Module for WebP decoding.

This is a LuaJIT FFI wrapper for libwebp.

@module ffi.webp
]]

local ffi = require("ffi")
local BB = require("ffi/blitbuffer")

require("ffi/libwebp_h")

-- local libwebp = ffi.load("libs/libwebp." .. (ffi.os == "OSX" and "7.dylib" or "so.7"))
-- We only need the stuff provided by libwebpdemux.so (which itself uses libwebp.so)
local libwebpdemux = ffi.load("libs/libwebpdemux." .. (ffi.os == "OSX" and "2.dylib" or "so.2"))

local Webp = {
    webp_decoder = nil,
    webp_image = nil,
    width = nil,
    height = nil,
    components = 4, -- always RGB32
    nb_frames = nil,
    cur_frame = nil,
}

function Webp:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Webp.fromFile(filename)
    local fh = io.open(filename, "rb")
    assert(fh, "couldn't open WebP file")
    local data = fh:read("*a")
    fh:close()
    return Webp.fromData(data)
end

function Webp.fromData(data, size)
    local webp_data = ffi.new("WebPData[1]")
    webp_data[0].bytes = ffi.cast("const unsigned char*", data)
    webp_data[0].size = size or #data

    -- Note: WebPAnimDecoderOptionsInit() and WebPAnimDecoderNew() are inline functions in demux.h.
    -- We need to use their ...Internal() versions.
    local dec_options = ffi.new("WebPAnimDecoderOptions[1]")
    local ret = libwebpdemux.WebPAnimDecoderOptionsInitInternal(dec_options, libwebpdemux.WEBP_DEMUX_ABI_VERSION);
    assert(ret ~= 0, "libwebp WebPAnimDecoderOptionsInit() failed.")
    dec_options[0].color_mode = libwebpdemux.MODE_RGBA

    local decoder = libwebpdemux.WebPAnimDecoderNewInternal(webp_data, dec_options, libwebpdemux.WEBP_DEMUX_ABI_VERSION)
    -- check for nil for "NULL in case of parsing error, invalid option or memory error"
    assert(decoder ~= nil, "libwebp WebPAnimDecoderNew() failed (parsing or memory error).")

    local anim_info = ffi.new("WebPAnimInfo[1]")
    ret = libwebpdemux.WebPAnimDecoderGetInfo(decoder, anim_info)
    assert(ret ~= 0, "libwebp WebPAnimDecoderGetInfo() failed.")

    if anim_info[0].frame_count > 1 and type(data) ~= "string" then
        -- When called from CreDocument:getImageFromPosition(), data is a "userdata" wrapping
        -- a buffer malloc()'ed by cre.cpp, which is freed as soon as getImageFromPosition()
        -- returns, as we usually don't need it after having rendered the image data to
        -- a blitbuffer.
        -- With animated multiframes images, we keep the decoder object: GifLib is fine with
        -- data being gone, but libwebp is not.
        -- We could have renderImageData() return a flag to state that the data should not
        -- be free()d, but it would complexify the return values and their handling.
        -- So, keep it simple: make a copy of the external buffer into an interned Lua
        -- string, that we will keep alive.
        libwebpdemux.WebPAnimDecoderDelete(decoder) -- give up with current decoder
        data = ffi.string(data, size)
        -- And call again this same function, now with data a real Lua string.
        return Webp.fromData(data, size)
    end

    return Webp:new{
        webp_decoder = decoder,
        -- (We don't need to keep webp_data and dec_options alive, which just got
        -- their values read and used and are not stored in the above objects.)
        nb_frames = anim_info[0].frame_count,
        width = anim_info[0].canvas_width,
        height = anim_info[0].canvas_height,
        -- we need to keep this interned Lua string alive as long as decoder is alive.
        -- (To not be bothered with large binary data when using logger(webp), we don't
        -- store the string itself, but a function referencing it as an upvalue, as
        -- functions are just dumped as their address by logger.)
        _input_data_holder = function() return data end,
    }
end

function Webp:getFrameImage(number, no_copy)
    if number < 1 then number = 1 end
    if number > self.nb_frames then number = self.nb_frames end

    if not self.webp_image then
        self.webp_image = ffi.new("unsigned char*[1]")
        -- WebPAnimDecoderGetNext() will update this pointer with the
        -- address of one of its two internal bitmap data buffers.
        -- As such, it is only valid until the next call.
    end
    if not self.cur_frame then
        self.cur_frame = 0
    end
    if number < self.cur_frame then
        libwebpdemux.WebPAnimDecoderReset(self.webp_decoder) -- Rewind to start
        self.cur_frame = 0
        -- Note: browsing frames forward is fast, but because of this, browsing
        -- late frames backward can be noticeably slower.
    end
    -- Render all frames from cur_frame to the one requested (this is needed as
    -- webp frames can be partial and need to be blended over the previous frame)
    local timestamp = ffi.new("int[1]") -- not used by us
    while self.cur_frame < number do
        local ret = libwebpdemux.WebPAnimDecoderGetNext(self.webp_decoder, self.webp_image, timestamp)
        assert(ret ~= 0, "libwebp WebPAnimDecoderGetNext() failed (parsing or decoding error, or no more frames).")
        self.cur_frame = self.cur_frame + 1
    end
    local image_bb = BB.new(self.width, self.height, BB.TYPE_BBRGB32, self.webp_image[0])
    if no_copy then
        -- If the caller doesn't need this bb to live after next frame image is called,
        -- or if it does some scaling or a copy itself, it can provide no_copy=true.
        return image_bb
    end
    -- Otherwise, make a copy of the internal libwebp image buffer
    return image_bb:copy()
end

function Webp:close()
    libwebpdemux.WebPAnimDecoderDelete(self.webp_decoder)
    self.webp_image = nil
    self.webp_decoder = nil
    self._input_data_holder = nil
end

return Webp
