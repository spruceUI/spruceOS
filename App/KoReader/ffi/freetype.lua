--[[--
Freetype library interface (text rendering)

@module ffi.freetype
--]]

local bit = require("bit")
local ffi = require("ffi")
local Blitbuffer = require("ffi/blitbuffer")
local C = ffi.C

-- the header definitions
require("ffi/freetype_h")

local ft2
if ffi.os == "Windows" then
    ft2 = ffi.load("libs/libfreetype-6.dll")
elseif ffi.os == "OSX" then
    ft2 = ffi.load("libs/libfreetype.6.dylib")
else
    ft2 = ffi.load("libs/libfreetype.so.6")
end

local freetypelib = ffi.new("FT_Library[1]")
assert(ft2.FT_Init_FreeType(freetypelib) == 0, "Couldn't initialize Freetype!")
freetypelib = ffi.gc(freetypelib[0], ft2.FT_Done_Library)

local function done_face(face)
    ffi.gc(face, nil)
    local lib = face.generic.data
    assert(ft2.FT_Done_Face(face) == 0, "freetype error when freeing face")
    ft2.FT_Done_Library(lib)
end

local function new_face(filename, faceindex)
    local facept = ffi.new("FT_Face[1]")
    local err = ft2.FT_New_Face(freetypelib, filename, faceindex, facept)
    if err ~= 0 then
        error("Failed to load font '"..filename.."', freetype error code: "..err)
    end
    local face = ffi.gc(facept[0], done_face)
    ft2.FT_Reference_Library(freetypelib)
    face.generic.data = freetypelib
    return face
end

local function done_size(size)
    ffi.gc(size, nil)
    local face = size.face
    local refcount = ffi.cast("int *", size.generic.data)
    assert(refcount[0] > 0)
    refcount[0] = refcount[0] - 1
    if refcount[0] > 0 then
        return
    end
    C.free(refcount)
    assert(ft2.FT_Done_Size(size) == 0, "freetype error when freeing size")
    local lib = face.generic.data
    ft2.FT_Done_Face(face)
    ft2.FT_Done_Library(lib)
end

local function new_size(face)
    local sizept = ffi.new("FT_Size[1]")
    local err = ft2.FT_New_Size(face, sizept)
    if err ~= 0 then
        error("Failed to create font size, freetype error code: "..err)
    end
    ft2.FT_Reference_Face(face)
    ft2.FT_Reference_Library(face.generic.data)
    local size = ffi.gc(sizept[0], done_size)
    local refcount = ffi.cast("int *", C.malloc(ffi.sizeof("int")))
    size.generic.data = refcount
    refcount[0] = 1;
    return size
end

local FT = {}

local FTSize_mt = {__index={}}

function FTSize_mt.__index:hasGlyph(char)
    assert(ft2.FT_Activate_Size(self) == 0, "failed to activate font size")
    return ft2.FT_Get_Char_Index(self.face, char) ~= 0
end

function FTSize_mt.__index:renderGlyph(char, bold)
    assert(ft2.FT_Activate_Size(self) == 0, "failed to activate font size")
    assert(ft2.FT_Load_Char(self.face, char, ft2.FT_LOAD_RENDER) == 0, "freetype error")
    local glyph = self.face.glyph
    if bold then ft2.FT_GlyphSlot_Embolden(glyph) end
    local bitmap = glyph.bitmap
    -- NOTE: depending on the char, bitmap_top (bearingY) can be larger than
    -- bb:getHeight(). For example: ×. This means the char needs to be drawn
    -- above baseline.
    return {
        bb = Blitbuffer.new(bitmap.width, bitmap.rows, Blitbuffer.TYPE_BB8, bitmap.buffer, bitmap.pitch):copy(),
        l  = glyph.bitmap_left,
        t  = glyph.bitmap_top,
        r  = tonumber(glyph.metrics.horiAdvance / 64),
        ax = tonumber(glyph.advance.x / 64),
        ay = tonumber(glyph.advance.y / 64)
    }
end

-- For use with glyph index and metrics returned by Harfbuzz
-- These flags should be sync'ed with those used in xtext.cpp getHbFontData()
local FT_Load_Glyph_flags = bit.bor(ft2.FT_LOAD_DEFAULT, ft2.FT_LOAD_TARGET_LIGHT)
-- FT_Load_Glyph_flags = bit.bor(FT_Load_Glyph_flags, ft2.FT_LOAD_FORCE_AUTOHINT)
-- (No hinting, as it would mess synthetized bold)
FT_Load_Glyph_flags = bit.bor(FT_Load_Glyph_flags, ft2.FT_LOAD_NO_HINTING, ft2.FT_LOAD_NO_AUTOHINT)

function FTSize_mt.__index:renderGlyphByIndex(index, embolden_half_strength)
    assert(ft2.FT_Activate_Size(self) == 0, "failed to activate font size")
    assert(ft2.FT_Load_Glyph(self.face, index, FT_Load_Glyph_flags) == 0, "freetype error")
    local glyph = self.face.glyph
    -- We can't use FT_GlyphSlot_Embolden() as it updates the
    -- glyph metrics from the font, and would mess the adjusments
    -- provided by Harfbuzz. We need to use FT_Outline_Embolden
    -- and FT_Outline_Translate in a way to not move metrics.
    if embolden_half_strength and glyph.format == ft2.FT_GLYPH_FORMAT_OUTLINE then
        ft2.FT_Outline_Embolden(glyph.outline, 2*embolden_half_strength);
        ft2.FT_Outline_Translate(glyph.outline, -embolden_half_strength, -embolden_half_strength);
    end
    ft2.FT_Render_Glyph(glyph, ft2.FT_RENDER_MODE_NORMAL);
    local bitmap = glyph.bitmap
    return {
        bb = Blitbuffer.new(bitmap.width, bitmap.rows, Blitbuffer.TYPE_BB8, bitmap.buffer, bitmap.pitch):copy(),
        l  = glyph.bitmap_left,
        t  = glyph.bitmap_top,
        r  = tonumber(glyph.metrics.horiAdvance / 64),
        ax = tonumber(glyph.advance.x / 64),
        ay = tonumber(glyph.advance.y / 64)
    }
end

function FTSize_mt.__index:getEmboldenHalfStrength(factor)
    assert(ft2.FT_Activate_Size(self) == 0, "failed to activate font size")
    -- See crengine/src/lvfntman.cpp setEmbolden() for details
    if not factor then
        factor = 1/2 -- (a bit bolder than crengine which uses 3/8)
    end
    local strength = ft2.FT_MulFix(self.face.units_per_EM, self.metrics.y_scale) / 24
        -- Note: this is a 64bit integer cdata, that we need to return
        -- as such. So, we need to do C arithmetic with it, or we'll
        -- have it converted to a Lua number.
    local factor_int64 = ffi.new("int64_t", 1024*factor)
    strength = strength * factor_int64 / 1024
    return strength
end

function FTSize_mt.__index:getKerning(leftcharcode, rightcharcode)
    assert(ft2.FT_Activate_Size(self) == 0, "failed to activate font size")
    local kerning = ffi.new("FT_Vector")
    assert(ft2.FT_Get_Kerning(self.face, leftcharcode, rightcharcode,
        ft2.FT_KERNING_DEFAULT, kerning) == 0,
        "freetype error when getting kerning.")
    return tonumber(kerning.x / 64)
end

function FTSize_mt.__index:getHeightAndAscender()
    assert(ft2.FT_Activate_Size(self) == 0, "failed to activate font size")
    local face = self.face
    local y_scale = self.metrics.y_ppem / face.units_per_EM
    return face.height * y_scale, face.ascender * y_scale
end

function FTSize_mt.__index:getInfo()
    assert(ft2.FT_Activate_Size(self) == 0, "failed to activate font size")
    local face = self.face
    local finfo = {
        name = ffi.string(face.family_name),
        -- Style
        mono = bit.band(tonumber(face.face_flags), ft2.FT_FACE_FLAG_FIXED_WIDTH) ~= 0,
        hint = bit.band(tonumber(face.face_flags), ft2.FT_FACE_FLAG_HINTER) ~= 0,
        bold = bit.band(tonumber(face.style_flags), ft2.FT_STYLE_FLAG_BOLD) ~= 0,
        italic = bit.band(tonumber(face.style_flags), ft2.FT_STYLE_FLAG_ITALIC) ~= 0,
        serif = nil,
        ui = false,
        names = nil,
    }
    -- In practice, just going by latin name can tell us more than the depressingly absent tags
    finfo.ui = finfo.name:match("UI$") ~= nil
    local lname = finfo.name:lower()
    if lname:match("serif") then
        finfo.serif = true
    elseif lname:match("sans") then
        finfo.serif = false
    elseif bit.band(tonumber(face.face_flags), ft2.FT_FACE_FLAG_SFNT) ~= 0 then
        local os2 = ft2.FT_Get_Sfnt_Table(face, ft2.FT_SFNT_OS2)
        if os2 ~= nil then
            local kls = tonumber(ffi.cast("TT_OS2*", os2).sFamilyClass)
            if kls ~= 0 then -- 0 is usually bogus
                -- class 8 = sans, otherwise serif
                finfo.serif = bit.band(kls, 0x0800) == 0
            end
        end
        if finfo.serif == nil then
            --TODO: Maybe it's worth to consult panose tables too?
            finfo.serif = true
        end
    end
    return finfo
end

function FTSize_mt.__index:done()
    done_size(self)
end

local FTSizeType = ffi.metatype("struct FT_SizeRec_", FTSize_mt) -- luacheck: ignore 211

local faces_cache = setmetatable({}, {__mode="v"})

function FT.newFaceSize(filename, pxsize, faceindex)
    if pxsize == nil then pxsize = 16*64 end
    if faceindex == nil then faceindex = 0 end
    local cache_key = string.format('%s:%d', filename, faceindex)
    local face = faces_cache[cache_key]
    if not face then
        face = new_face(filename, faceindex)
        faces_cache[cache_key] = face
    end
    local size = new_size(face)
    -- Activate the new size and setup its pixel sizes.
    if ft2.FT_Activate_Size(size) ~= 0 or ft2.FT_Set_Pixel_Sizes(face, 0, pxsize) ~= 0 then
        size:done()
        error("freetype error")
    end
    -- if face.charmap == nil then
        --TODO
    -- end
    return size
end

function FT.getFaceCount(filename, info)
    -- Probes number of faces available within the font file
    local success, face = pcall(new_face, filename, -1)
    if not success then return nil end
    local nfaces = tonumber(face.num_faces)
    done_face(face)
    return nfaces
end

return FT
