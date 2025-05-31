local ffi = require("ffi")
local BB = require("ffi/blitbuffer")

local Pic = {}

--[[
start of pic page type
--]]
local PicPage = {}

function PicPage:extend(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end
-- Keep to our usual semantics (extend for class definitions, new for new instances)
PicPage.new = PicPage.extend

function PicPage:getSize(dc)
    local zoom = dc:getZoom()
    return self.width * zoom, self.height * zoom
end

function PicPage:getUsedBBox()
    return 0.01, 0.01, -0.01, -0.01
end

function PicPage:close()
end

--[[
-- NOTE: This is a plain table, that won't work on Lua 5.1/LuaJIT
--       Comment this out since this a currently a no-op anyway.
PicPage.__gc = PicPage.close
--]]

function PicPage:draw(dc, bb)
    local scaled_bb = self.image_bb:scale(bb:getWidth(), bb:getHeight())
    bb:blitFullFrom(scaled_bb, 0, 0)
    scaled_bb:free()
end


--[[
start of pic document
--]]
local PicDocument = {}

function PicDocument:extend(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end
PicDocument.new = PicDocument.extend

function PicDocument:openPage()
    local page = PicPage:new{
        width = self.width,
        height = self.height,
        image_bb = self.image_bb,
        doc = self,
    }
    return page
end

function PicDocument:getToc()
    return {}
end

function PicDocument:getPages()
    return 1
end

function PicDocument:getCacheSize()
    return 0
end

function PicDocument:cleanCache()
end

function PicDocument:getOriginalPageSize()
    return self.width, self.height, self.components
end

function PicDocument:close()
    if self.image_bb ~= nil then
        self.image_bb:free()
        self.image_bb = nil
    end
end

--[[
-- NOTE: Ditto, plain table, and essentially a no-op since BlitBuffer already handles the cdata finalizer.
PicDocument.__gc = PicDocument.close
--]]

--[[
GIF handling (an animated GIF will make a document with multiple pages)
--]]
local giflib
local ensure_giflib_loaded = function()
    if giflib then return end
    require("ffi/giflib_h")
    if ffi.os == "Windows" then
        giflib = ffi.load("libs/libgif-7.dll")
    elseif ffi.os == "OSX" then
        giflib = ffi.load("libs/libgif.7.dylib")
    else
        giflib = ffi.load("libs/libgif.so.7")
    end
end

local GifPage = PicPage:extend{}
function GifPage:close()
    -- with Gifs, the blitbuffers are per page
    if self.image_bb ~= nil then
        self.image_bb:free()
        self.image_bb = nil
    end
end

local GifDocument = PicDocument:extend{
    giffile = nil,
}
function GifDocument:getPages()
    return self.giffile.ImageCount
end
function GifDocument:getOriginalPageSize(number)
    -- subsequent frames may have a smaller size than 1 frame
    local i = self.giffile.SavedImages[0]
    return i.ImageDesc.Width, i.ImageDesc.Height, 4 -- components
end
function GifDocument:openPage(number)
    ensure_giflib_loaded()
    -- If there are multiple frames (animated GIF), a standalone
    -- frame may not be enough (it may be smaller than the first frame,
    -- and have some transparency): we need to paste it (and all the
    -- previous frames) over the first frame
    -- Here, because requesting a random number is possible, we redo all the
    -- pastes from first frame till requested frame number: it could be optimized
    local i = self.giffile.SavedImages[0]
    local width = i.ImageDesc.Width
    local height = i.ImageDesc.Height
    local bb = BB.new(width, height, BB.TYPE_BBRGB32)
    bb:fill(BB.COLOR_WHITE) -- fill with white in case first frame has transparency

    local gcb = ffi.new("GraphicsControlBlock") -- re-used with each frame
    local framenum = 1
    while framenum <= number and framenum <= self.giffile.ImageCount do
        -- print("frame "..framenum)

        -- get transparency (index into palette) and disposal_mode (how to draw
        -- frame over previous ones) from Graphics Control Extension
        local transparent_color = nil
        local disposal_mode = nil
        if giflib.DGifSavedExtensionToGCB(self.giffile, framenum-1, gcb) == 1 then
            if gcb.TransparentColor ~= giflib.NO_TRANSPARENT_COLOR then
                transparent_color = gcb.TransparentColor
            end
            if gcb.DisposalMode ~= giflib.DISPOSAL_UNSPECIFIED then
                disposal_mode = gcb.DisposalMode
            end
        end
        -- See http://webreference.com/content/studio/disposal.html
        -- (not tested, all found animated gif have DISPOSE_DO_NOT
        if disposal_mode == giflib.DISPOSE_BACKGROUND then
            bb:fill(BB.COLOR_WHITE) -- fill with white
        -- elseif disposal_mode == giflib.DISPOSE_PREVIOUS then
            -- Rare (no sample to test with), and not supported for now: we should
            -- keep a copy of the last bb drawn widh DISPOSE_DO_NOT
        -- else: giflib.DISPOSE_DO_NOT or DISPOSAL_UNSPECIFIED: draw over previous frame
        end

        -- build palette from frame or global color map
        local cmap = i.ImageDesc.ColorMap ~= nil and i.ImageDesc.ColorMap or self.giffile.SColorMap
        local palette={}
        for c=0, cmap.ColorCount-1 do
            local color = cmap.Colors[c]
            palette[c] = BB.ColorRGB32(color.Red, color.Green, color.Blue, 0xFF)
        end

        -- Draw current frame on our bb
        local f_w, f_h = i.ImageDesc.Width, i.ImageDesc.Height
        local f_x, f_y = i.ImageDesc.Left, i.ImageDesc.Top
        local p = i.RasterBits
        for y = f_y, f_y+f_h-1 do
            for x = f_x, f_x+f_w-1 do
                if not transparent_color or p[0] ~= transparent_color then
                    bb:setPixel(x, y, palette[p[0]])
                end
                p = p + 1
            end
        end

        framenum = framenum + 1
        if framenum <= self.giffile.ImageCount then
            i = self.giffile.SavedImages[framenum-1]
        end
    end

    local page = GifPage:new{
        width = width,
        height = height,
        image_bb = bb,
        doc = self,
    }

    return page
end
function GifDocument:close()
    ensure_giflib_loaded()
    local err = ffi.new("int[1]")
    if giflib.DGifCloseFile(self.giffile, err) ~= giflib.GIF_OK then
        error(string.format("error closing/deallocating GIF: %s",
            ffi.string(giflib.GifErrorString(err[0]))))
    end
    self.giffile = nil
end

function Pic.openGIFDocument(filename)
    ensure_giflib_loaded()
    local err = ffi.new("int[1]")
    local giffile = giflib.DGifOpenFileName(filename, err)
    if giffile == nil then
        error(string.format("Cannot read GIF file: %s",
            ffi.string(giflib.GifErrorString(err[0]))))
    end
    if giflib.DGifSlurp(giffile) ~= giflib.GIF_OK then
        giflib.DGifCloseFile(giffile, err)
        error(string.format("Cannot parse GIF file: %s",
            ffi.string(giflib.GifErrorString(giffile.Error))))
    end
    return GifDocument:new{giffile = giffile}
end

function Pic.openGIFDocumentFromData(data, size)
    ensure_giflib_loaded()
    -- Create GIF from data pointer (from https://github.com/luapower/giflib)
    local function data_reader(r_data, r_size)
        r_data = ffi.cast('unsigned char*', r_data)
        return function(_, buf, sz)
            if sz < 1 or r_size < 1 then error('eof') end
            sz = math.min(r_size, sz)
            ffi.copy(buf, r_data, sz)
            r_data = r_data + sz
            r_size = r_size - sz
            return sz
        end
    end
    local read_cb = ffi.cast('InputFunc', data_reader(data, size))
    local err = ffi.new("int[1]")
    local giffile = giflib.DGifOpen(nil, read_cb, err)
    if giffile == nil then
        read_cb:free()
        error(string.format("Cannot read GIF file: %s",
            ffi.string(giflib.GifErrorString(err[0]))))
    end
    if giflib.DGifSlurp(giffile) ~= giflib.GIF_OK then
        giflib.DGifCloseFile(giffile, err)
        read_cb:free()
        error(string.format("Cannot parse GIF file: %s",
            ffi.string(giflib.GifErrorString(giffile.Error))))
    end
    read_cb:free()
    return GifDocument:new{giffile = giffile}
end

--[[
WebP handling (an animated WebP will make a document with multiple pages)
--]]
local WebpPage = PicPage:extend{}
function WebpPage:close()
    -- with WebP, the blitbuffers are per page
    if self.image_bb ~= nil then
        self.image_bb:free()
        self.image_bb = nil
    end
end

local WebpDocument = PicDocument:extend{
    webp = nil, -- ffi/webp instance
}
function WebpDocument:getPages()
    return self.webp.nb_frames
end
function WebpDocument:getOriginalPageSize(number)
    return self.webp.width, self.webp.height, self.webp.components
end
function WebpDocument:openPage(number)
    local bb = self.webp:getFrameImage(number)
    local page = WebpPage:new{
        width = self.webp.width,
        height = self.webp.height,
        image_bb = bb,
        doc = self,
    }
    return page
end
function WebpDocument:close()
    self.webp:close()
end

function Pic.openWebPDocument(filename)
    local WebP = require("ffi/webp")
    local webp = WebP.fromFile(filename)
    return WebpDocument:new{ webp = webp }
end

function Pic.openWebPDocumentFromData(data, size)
    local WebP = require("ffi/webp")
    local webp = WebP.fromData(data, size)
    return WebpDocument:new{ webp = webp }
end

--[[
PNG handling
--]]
function Pic.openPNGDocument(filename)
    local req_n
    local bbtype
    if Pic.color then
        req_n = 3
    else
        -- NOTE: LodePNG will NOT do RGB -> Grayscale conversions for us, for design reasons (multiple ways to do it, lossy).
        --       So we can only *ask* to keep grayscale PNGs as-is, but we might actually be getting fed back a RGB24 one ;).
        req_n = 1
    end

    local Png = require("ffi/png")
    local ok, re = Png.decodeFromFile(filename, req_n)
    if not ok then error(re) end

    if re.ncomp == 1 then bbtype = BB.TYPE_BB8
    elseif re.ncomp == 2 then bbtype = BB.TYPE_BB8A
    elseif re.ncomp == 3 then bbtype = BB.TYPE_BBRGB24
    elseif re.ncomp == 4 then bbtype = BB.TYPE_BBRGB32
    else
        if re.data then
            ffi.C.free(re.data)
        end
        error("unsupported number of color components")
    end

    local doc = PicDocument:new{width=re.width, height=re.height}
    doc.image_bb = BB.new(re.width, re.height, bbtype, re.data)
    doc.components = re.ncomp

    -- Mark buffer for freeing when Blitbuffer is freed:
    doc.image_bb:setAllocated(1)
    return doc
end

--[[
JPG handling
--]]
function Pic.openJPGDocument(filename)
    local Jpeg = require("ffi/jpeg")
    local image, w, h, components = Jpeg.openDocument(filename, Pic.color)

    local doc = PicDocument:new{width=w, height=h}
    doc.image_bb = image
    doc.components = components

    return doc
end

function Pic.openJPGDocumentFromMem(data)
    local Jpeg = require("ffi/jpeg")
    local image, w, h, components = Jpeg.openDocumentFromMem(data, Pic.color)

    local doc = PicDocument:new{width=w, height=h}
    doc.image_bb = image
    doc.components = components

    return doc
end

--[[
start of pic module API
--]]
function Pic.openDocument(filename)
    local extension = string.lower(string.match(filename, ".+%.([^.]+)") or "")
    if extension == "jpg" or extension == "jpeg" then
        return Pic.openJPGDocument(filename)
    elseif extension == "png" then
        return Pic.openPNGDocument(filename)
    elseif extension == "gif" then
        return Pic.openGIFDocument(filename)
    elseif extension == "webp" then
        return Pic.openWebPDocument(filename)
    else
        error("Unsupported image format")
    end
end

return Pic
