local ffi = require("ffi")
local C = ffi.C

require("ffi/koptcontext_h")
require("ffi/leptonica_h")
local Blitbuffer = require("ffi/blitbuffer")
local leptonica, k2pdfopt
if ffi.os == "Windows" then
    leptonica = ffi.load("libs/liblept-5.dll")
    k2pdfopt = ffi.load("libs/libk2pdfopt-2.dll")
elseif ffi.os == "OSX" then
    leptonica = ffi.load("libs/liblept.5.dylib")
    k2pdfopt = ffi.load("libs/libk2pdfopt.2.dylib")
else
    leptonica = ffi.load("libs/liblept.so.5")
    k2pdfopt = ffi.load("libs/libk2pdfopt.so.2")
end

local KOPTContext = {
    k2pdfopt = k2pdfopt -- offer the libraries' functions to other users
}
local KOPTContext_mt = {__index={}}

local __VERSION__ = "1.0.0"

function KOPTContext_mt.__index:setBBox(x0, y0, x1, y1)
    self.bbox.x0, self.bbox.y0, self.bbox.x1, self.bbox.y1 = x0, y0, x1, y1
end
function KOPTContext_mt.__index:setTrim(trim) self.trim = trim end
function KOPTContext_mt.__index:setWrap(wrap) self.wrap = wrap end
function KOPTContext_mt.__index:setWhite(white) self.white = white end
function KOPTContext_mt.__index:setIndent(indent) self.indent = indent end
function KOPTContext_mt.__index:setRotate(rotate) self.rotate = rotate end
function KOPTContext_mt.__index:setColumns(columns) self.columns = columns end
function KOPTContext_mt.__index:setDeviceDim(w, h) self.dev_width, self.dev_height = w, h end
function KOPTContext_mt.__index:setDeviceDPI(dpi) self.dev_dpi = dpi end
function KOPTContext_mt.__index:setStraighten(straighten) self.straighten = straighten end
function KOPTContext_mt.__index:setJustification(justification) self.justification = justification end
function KOPTContext_mt.__index:setWritingDirection(direction) self.writing_direction = direction end
function KOPTContext_mt.__index:setMargin(margin) self.margin = margin end
function KOPTContext_mt.__index:setZoom(zoom) self.zoom = zoom end
function KOPTContext_mt.__index:setQuality(quality) self.quality = quality end
function KOPTContext_mt.__index:setContrast(contrast) self.contrast = contrast end
function KOPTContext_mt.__index:setDefectSize(defect_size) self.defect_size = defect_size end
function KOPTContext_mt.__index:setLineSpacing(line_spacing) self.line_spacing = line_spacing end
function KOPTContext_mt.__index:setWordSpacing(word_spacing) self.word_spacing = word_spacing end
function KOPTContext_mt.__index:setLanguage(language)
    if self.language then
        C.free(self.language)
        self.language = nil
    end
    if language then
        -- As `self` is a struct, and `self.language` a `char *`,
        -- we need to make a C copy of the language string.
        self.language = C.strdup(language)
    end
end

function KOPTContext_mt.__index:setDebug() self.debug = 1 end
function KOPTContext_mt.__index:setCJKChar() self.cjkchar = 1 end
function KOPTContext_mt.__index:setPreCache() self.precache = 1 end

function KOPTContext_mt.__index:getTrim() return self.trim end
function KOPTContext_mt.__index:getZoom() return self.zoom end
function KOPTContext_mt.__index:getWrap() return self.wrap end
function KOPTContext_mt.__index:isPreCache() return self.precache end
function KOPTContext_mt.__index:getLanguage() return ffi.string(self.language) end
function KOPTContext_mt.__index:getPageDim() return self.page_width, self.page_height end
function KOPTContext_mt.__index:getBBox(x0, y0, x1, y1) return self.bbox.x0, self.bbox.y0, self.bbox.x1, self.bbox.y1 end

function KOPTContext_mt.__index:copyDestBMP(src)
    if src.dst.bpp == 8 or src.dst.bpp == 32 then
        k2pdfopt.bmp_copy(self.dst, src.dst)
    end
end

function KOPTContext_mt.__index:dstToBlitBuffer()
    local bb
    if self.dst.bpp == 8 then
        bb = Blitbuffer.new(self.dst.width, self.dst.height, Blitbuffer.TYPE_BB8, self.dst.data):copy()
    elseif self.dst.bpp == 24 then
        bb = Blitbuffer.new(self.dst.width, self.dst.height, Blitbuffer.TYPE_BBRGB24, self.dst.data):copy()
    elseif self.dst.bpp == 32 then
        bb = Blitbuffer.new(self.dst.width, self.dst.height, Blitbuffer.TYPE_BBRGB32, self.dst.data):copy()
    end
    return bb
end

function KOPTContext_mt.__index:getWordBoxes(bmp, x, y, w, h, box_type)
    local boxa = ffi.new("BOXA[1]")
    local nai = ffi.new("NUMA[1]")
    local counter_l = ffi.new("int[1]")
    local nr_word, current_line
    local counter_w, counter_cw
    local l_x0, l_y0, l_x1, l_y1

    if box_type == 0 then
        k2pdfopt.k2pdfopt_get_reflowed_word_boxes(self,
            bmp == "src" and self.src or self.dst, x, y, w, h)
        boxa = self.rboxa
        nai = self.rnai
    elseif box_type == 1 then
        k2pdfopt.k2pdfopt_get_native_word_boxes(self,
            bmp == "src" and self.src or self.dst, x, y, w, h)
        boxa = self.nboxa
        nai = self.nnai
    end

    if boxa == nil or nai == nil then return end

    -- get number of lines in this area
    nr_word = leptonica.boxaGetCount(boxa)
    assert(nr_word == leptonica.numaGetCount(nai))

    local boxes = {}
    counter_w = 0
    while counter_w < nr_word do
        leptonica.numaGetIValue(nai, counter_w, counter_l)
        current_line = counter_l[0]
        -- sub-table that contains words in a line
        local lbox = {}
        boxes[counter_l[0]+1] = lbox
        counter_cw = 0
        l_x0, l_y0, l_x1, l_y1 = 9999, 9999, 0, 0
        while current_line == counter_l[0] and counter_w < nr_word do
            local box = leptonica.boxaGetBox(boxa, counter_w, C.L_CLONE)
            -- update line box
            l_x0 = box.x < l_x0 and box.x or l_x0
            l_y0 = box.y < l_y0 and box.y or l_y0
            l_x1 = box.x + box.w > l_x1 and box.x + box.w or l_x1
            l_y1 = box.y + box.h > l_y1 and box.y + box.h or l_y1
            -- box for a single word
            lbox[counter_cw+1] = {
                x0 = box.x, y0 = box.y,
                x1 = box.x + box.w,
                y1 = box.y + box.h,
            }
            counter_w, counter_cw = counter_w + 1, counter_cw + 1
            if counter_w < nr_word then
                leptonica.numaGetIValue(nai, counter_w, counter_l)
            end
        end
        if current_line ~= counter_l[0] then counter_w = counter_w - 1 end
        -- box for a whole line
        lbox.x0, lbox.y0, lbox.x1, lbox.y1 = l_x0, l_y0, l_x1, l_y1
        counter_w = counter_w + 1
    end
    return boxes, nr_word
end

function KOPTContext_mt.__index:getReflowedWordBoxes(bmp, x, y, w, h)
    return self:getWordBoxes(bmp, x, y, w, h, 0)
end

function KOPTContext_mt.__index:getNativeWordBoxes(bmp, x, y, w, h)
    return self:getWordBoxes(bmp, x, y, w, h, 1)
end

function KOPTContext_mt.__index:reflowToNativePosTransform(xc, yc, wr, hr)
    local function wrectmap_reflow_distance(wrmap, x, y)
        local function wrectmap_reflow_inside(wrmap_inside, x_inside, y_inside)
            return k2pdfopt.wrectmap_inside(wrmap_inside, x_inside, y_inside) ~= 0
        end
        if wrectmap_reflow_inside(wrmap, x, y) then
            return 0
        else
            local x0, y0 = x, y
            local x1 = wrmap.coords[1].x + wrmap.coords[2].x / 2
            local y1 = wrmap.coords[1].y + wrmap.coords[2].y / 2
            return (x0 - x1)*(x0 - x1) + (y0 - y1)*(y0 - y1)
        end
    end

    local m = 0
    for i = 0, self.rectmaps.n - 1 do
        if wrectmap_reflow_distance(self.rectmaps.wrectmap + m, xc, yc) >
            wrectmap_reflow_distance(self.rectmaps.wrectmap + i, xc, yc) then
            m = i
        end
    end
    if self.rectmaps.n > m then
        local rectmap = self.rectmaps.wrectmap + m
        local x = rectmap.coords[0].x*self.dev_dpi*self.quality/rectmap.srcdpiw
        local y = rectmap.coords[0].y*self.dev_dpi*self.quality/rectmap.srcdpih
        local w = rectmap.coords[2].x*self.dev_dpi*self.quality/rectmap.srcdpiw
        local h = rectmap.coords[2].y*self.dev_dpi*self.quality/rectmap.srcdpih
        return (x+w*wr)/self.zoom+self.bbox.x0, (y+h*hr)/self.zoom+self.bbox.y0
    end
end

function KOPTContext_mt.__index:nativeToReflowPosTransform(xc, yc)
    local function wrectmap_native_distance(wrmap, x0, y0)
        local x = wrmap.coords[0].x*self.dev_dpi*self.quality/wrmap.srcdpiw
        local y = wrmap.coords[0].y*self.dev_dpi*self.quality/wrmap.srcdpih
        local w = wrmap.coords[2].x*self.dev_dpi*self.quality/wrmap.srcdpiw
        local h = wrmap.coords[2].y*self.dev_dpi*self.quality/wrmap.srcdpih
        local function wrectmap_native_inside(wrmap_inside, x0_inside, y0_inside)
            return x <= x0_inside and y <= y0_inside
                    and x + w >= x0_inside
                    and y + h >= y0_inside
        end
        if wrectmap_native_inside(wrmap, x0, y0) then
            return 0
        else
            local x1, y1 = x + w/2, y + h/2
            return (x0 - x1)*(x0 - x1) + (y0 - y1)*(y0 - y1)
        end
    end

    local m = 0
    local x0, y0 = (xc - self.bbox.x0) * self.zoom, (yc - self.bbox.y0) * self.zoom
    for i = 0, self.rectmaps.n - 1 do
        if wrectmap_native_distance(self.rectmaps.wrectmap + m, x0, y0) >
            wrectmap_native_distance(self.rectmaps.wrectmap + i, x0, y0) then
            m = i
        end
    end
    local rectmap = self.rectmaps.wrectmap + m
    return rectmap.coords[1].x + rectmap.coords[2].x/2, rectmap.coords[1].y + rectmap.coords[2].y/2
end

function KOPTContext_mt.__index:getTOCRWord(bmp, x, y, w, h, datadir, lang, ocr_type, allow_spaces, std_proc)
    local word = ffi.new("char[256]")
    k2pdfopt.k2pdfopt_tocr_single_word(bmp == "src" and self.src or self.dst,
        x, y, w, h, word, 255, ffi.cast("char*", datadir), ffi.cast("char*", lang),
        ocr_type, allow_spaces, std_proc)
    return ffi.string(word)
end

function KOPTContext_mt.__index:getAutoBBox()
    -- fall back to default writing direction when detecting bbox
    self:setWritingDirection(0)
    k2pdfopt.k2pdfopt_crop_bmp(self)
    local x0 = self.bbox.x0/self.zoom
    local y0 = self.bbox.y0/self.zoom
    local x1 = self.bbox.x1/self.zoom
    local y1 = self.bbox.y1/self.zoom
    return x0, y0, x1, y1
end

function KOPTContext_mt.__index:findPageBlocks()
    if self.src.data then
        local pixs = k2pdfopt.bitmap2pix(self.src,
            0, 0, self.src.width, self.src.height)
        local pixr = leptonica.pixThresholdToBinary(pixs, 128)
        leptonica.pixDestroy(ffi.new('PIX *[1]', pixs))

        local pixtb = ffi.new("PIX *[1]")
        local status = leptonica.pixGetRegionsBinary(pixr, nil, nil, pixtb, nil)
        if status == 0 then
            self.nboxa = leptonica.pixSplitIntoBoxa(pixtb[0], 5, 10, 20, 80, 10, 0)
            for i = 0, leptonica.boxaGetCount(self.nboxa) - 1 do
                local box = leptonica.boxaGetBox(self.nboxa, i, C.L_CLONE)
                leptonica.boxAdjustSides(box, box, -1, 0, -1, 0)
            end
            self.rboxa = leptonica.boxaCombineOverlaps(self.nboxa)
            self.page_width = leptonica.pixGetWidth(pixr)
            self.page_height = leptonica.pixGetHeight(pixr)

            -- uncomment this to show text blocks in situ
            --leptonica.pixWritePng("textblock-mask.png", pixtb[0], 0.0)

            leptonica.pixDestroy(ffi.new('PIX *[1]', pixtb))
        end
        leptonica.pixDestroy(ffi.new('PIX *[1]', pixr))
    end
end

function KOPTContext_mt.__index:getPanelFromPage(pos)
    local function isInRect(x, y, w, h, pos_x, pos_y)
        return x < pos_x and y < pos_y and x + w > pos_x and y + h > pos_y
    end

    if self.src.data then
        local pixs = k2pdfopt.bitmap2pix(self.src, 0, 0, self.src.width, self.src.height)
        local pixg
        if leptonica.pixGetDepth(pixs) == 32 then
            pixg = leptonica.pixConvertRGBToGrayFast(pixs)
        else
            pixg = leptonica.pixClone(pixs)
        end

        -- leptonica's threshold gets pixels lighter than X, we want to get
        -- pixels darker than X, to do that we invert the image, threshold it,
        -- and invert the result back. Math: ~(~img < X) <=> img > X
        local pix_inverted = leptonica.pixInvert(nil, pixg)
        local pix_thresholded = leptonica.pixThresholdToBinary(pix_inverted, 50)
        leptonica.pixInvert(pix_thresholded, pix_thresholded)

        -- find connected components (in our case panels)
        local bb = leptonica.pixConnCompBB(pix_thresholded, 8)

        local img_w = leptonica.pixGetWidth(pixs)
        local img_h = leptonica.pixGetHeight(pixs)
        local res

        for i = 0, leptonica.boxaGetCount(bb) - 1 do
            local box = leptonica.boxaGetBox(bb, i, C.L_CLONE)
            local pix_tmp = leptonica.pixClipRectangle(pixs, box, nil)
            local w = leptonica.pixGetWidth(pix_tmp)
            local h = leptonica.pixGetHeight(pix_tmp)
            -- check if it's panel or part of the panel, if it's part of the panel skip
            if w >= img_w / 8 and h >= img_h / 8 then
                if isInRect(box.x, box.y, box.w, box.h, pos.x, pos.y) then
                    res = {
                        x = box.x,
                        y = box.y,
                        w = box.w,
                        h = box.h,
                    }
                    leptonica.pixDestroy(ffi.new("PIX *[1]", pix_tmp))
                    leptonica.boxDestroy(ffi.new("BOX *[1]", box))
                    break -- we found panel, exit the loop and clean up memory
                end
            end
            leptonica.pixDestroy(ffi.new("PIX *[1]", pix_tmp))
            leptonica.boxDestroy(ffi.new("BOX *[1]", box))
        end

        -- free up memory
        leptonica.boxaDestroy(ffi.new("BOXA *[1]", bb))
        leptonica.pixDestroy(ffi.new("PIX *[1]", pixg))
        leptonica.pixDestroy(ffi.new("PIX *[1]", pix_thresholded))
        leptonica.pixDestroy(ffi.new("PIX *[1]", pix_inverted))
        leptonica.pixDestroy(ffi.new("PIX *[1]", pixs))
        return res
    end
end

--[[
-- get page block in location x, y both of which in range [0, 1] relative to page
-- width and height respectively
--]]
function KOPTContext_mt.__index:getPageBlock(x_rel, y_rel)
    local block = nil
    if self.src.data and self.nboxa ~= nil and self.rboxa ~= nil then
        local w, h = self:getPageDim()
        local tbox = leptonica.boxCreate(0, y_rel * h, w, 2)
        local boxa = leptonica.boxaClipToBox(self.nboxa, tbox)
        leptonica.boxDestroy(ffi.new('BOX *[1]', tbox))
        for i = 0, leptonica.boxaGetCount(boxa) - 1 do
            local box = leptonica.boxaGetBox(boxa, i, C.L_CLONE)
            leptonica.boxAdjustSides(box, box, -1, 0, -1, 0)
        end
        local boxatb = leptonica.boxaCombineOverlaps(boxa)
        leptonica.boxaDestroy(ffi.new('BOXA *[1]', boxa))
        local clipped_box, unclipped_box
        for i = 0, leptonica.boxaGetCount(boxatb) - 1 do
            local box = leptonica.boxaGetBox(boxatb, i, C.L_CLONE)
            if box.x / w <= x_rel and (box.x + box.w) / w >= x_rel then
                clipped_box = leptonica.boxCreate(box.x, 0, box.w, h)
            end
            leptonica.boxDestroy(ffi.new('BOX *[1]', box))
            if clipped_box ~= nil then break end
        end
        for i = 0, leptonica.boxaGetCount(self.rboxa) - 1 do
            local box = leptonica.boxaGetBox(self.rboxa, i, C.L_CLONE)
            if box.x / w <= x_rel and (box.x + box.w) / w >= x_rel
                and box.y / h <= y_rel and (box.y + box.h) / h >= y_rel then
                unclipped_box = leptonica.boxCreate(box.x, box.y, box.w, box.h)
            end
            leptonica.boxDestroy(ffi.new('BOX *[1]', box))
            if unclipped_box ~= nil then break end
        end
        if clipped_box ~= nil and unclipped_box ~= nil then
            local box = leptonica.boxOverlapRegion(clipped_box, unclipped_box)
            if box ~= nil then
                block = {
                    x0 = box.x / w, y0 = box.y / h,
                    x1 = (box.x + box.w) / w,
                    y1 = (box.y + box.h) / h,
                }
            end
            leptonica.boxDestroy(ffi.new('BOX *[1]', box))
        end
        if clipped_box ~= nil then
            leptonica.boxDestroy(ffi.new('BOX *[1]', clipped_box))
        end
        if unclipped_box ~= nil then
            leptonica.boxDestroy(ffi.new('BOX *[1]', unclipped_box))
        end

        -- uncomment this to show text blocks in situ
        --[[
        if block then
            local w, h = self.src.width, self.src.height
            local box = leptonica.boxCreate(block.x0*w, block.y0*h,
                (block.x1-block.x0)*w, (block.y1-block.y0)*h)
            local boxa = leptonica.boxaCreate(1)
            leptonica.boxaAddBox(boxa, box, C.L_COPY)
            local pixs = k2pdfopt.bitmap2pix(self.src,
                0, 0, self.src.width, self.src.height)
            local pixc = leptonica.pixDrawBoxaRandom(pixs, boxa, 8)
            leptonica.pixWritePng("textblock.png", pixc, 0.0)
            leptonica.pixDestroy(ffi.new('PIX *[1]', pixc))
            leptonica.boxaDestroy(ffi.new('BOXA *[1]', boxa))
            leptonica.boxDestroy(ffi.new('BOX *[1]', box))
        end
        --]]

        leptonica.boxaDestroy(ffi.new('BOXA *[1]', boxatb))
    end

    return block
end

--[[
-- draw highlights into pix and return leptonica pixmap
--]]
function KOPTContext_mt.__index:getSrcPix(pboxes, drawer)
    if self.src.data ~= nil then
        local pix1 = k2pdfopt.bitmap2pix(self.src,
            0, 0, self.src.width, self.src.height)
        if pboxes and drawer == "lighten" then
            local color = 0xFFFF0000
            local bbox = self.bbox
            local pix2 = leptonica.pixConvertTo32(pix1)
            leptonica.pixDestroy(ffi.new('PIX *[1]', pix1))
            for _, pbox in ipairs(pboxes) do
                local box = ffi.new("BOX[1]")
                box[0].x = pbox.x - bbox.x0
                box[0].y = pbox.y - bbox.y0
                box[0].w, box[0].h = pbox.w, pbox.h
                leptonica.pixMultiplyByColor(pix2, pix2, box,
                        ffi.new("uint32_t", color))
            end
            return pix2
        else
            return pix1
        end
    end
end

function KOPTContext_mt.__index:exportSrcPNGFile(pboxes, drawer, filename)
    local pix = self:getSrcPix(pboxes, drawer)
    if pix ~= nil then
        leptonica.pixWritePng(filename, pix, ffi.new("float", 0.0))
        leptonica.pixDestroy(ffi.new('PIX *[1]', pix))
    end
end

function KOPTContext_mt.__index:exportSrcPNGString(pboxes, drawer)
    local pix = self:getSrcPix(pboxes, drawer)
    if pix ~= nil then
        local pdata = ffi.new("char *[1]")
        local psize = ffi.new("size_t[1]")
        leptonica.pixWriteMemPng(pdata, psize, pix, 0.0)
        leptonica.pixDestroy(ffi.new('PIX *[1]', pix))
        if pdata[0] ~= nil then
           local pngstr = ffi.string(pdata[0], psize[0])
           C.free(pdata[0])
           return pngstr
       end
    end
end

function KOPTContext_mt.__index:optimizePage()
    k2pdfopt.k2pdfopt_optimize_bmp(self)
end

function KOPTContext_mt.__index:free()
    -- NOTE: Jump through a large amount of shitty hoops to avoid double-frees,
    --       now that __gc may actually call us on collection long after an earlier explicit free...
    --- @fixme: Invest in a saner KOPTContext struct, possibly with a private bool to store the free state,
    ---         àla BlitBuffer/lj-sqlite3...
    if self.rnai ~= nil then
        local rnai_pptr = ffi.new('NUMA *[1]', self.rnai)
        leptonica.numaDestroy(rnai_pptr)
        self.rnai = rnai_pptr[0]
    end
    if self.nnai ~= nil then
        local nnai_pptr = ffi.new('NUMA *[1]', self.nnai)
        leptonica.numaDestroy(nnai_pptr)
        self.nnai = nnai_pptr[0]
    end
    if self.rboxa ~= nil then
        local rboxa_pptr = ffi.new('BOXA *[1]', self.rboxa)
        leptonica.boxaDestroy(rboxa_pptr)
        self.rboxa = rboxa_pptr[0]
    end
    if self.nboxa ~= nil then
        local nboxa_pptr = ffi.new('BOXA *[1]', self.nboxa)
        leptonica.boxaDestroy(nboxa_pptr)
        self.nboxa = nboxa_pptr[0]
    end

    self:setLanguage(nil)

    -- Already guards against NULL data pointers
    k2pdfopt.bmp_free(self.src)
    -- Already guards against NULL data pointers
    k2pdfopt.bmp_free(self.dst)

    if self.rectmaps.n ~= 0 then
        k2pdfopt.wrectmaps_free(self.rectmaps)
    end
end

function KOPTContext_mt:__gc()
    self:free()
end

function KOPTContext_mt.__index:freeOCR() k2pdfopt.k2pdfopt_tocr_end() end

-- NOTE: KOPTContext is a cdata struct, which is what makes __gc works here ;).
local kctype = ffi.metatype("KOPTContext", KOPTContext_mt)

function KOPTContext.new()
    local kc = kctype()
    -- integer values
    kc.trim = 1
    kc.wrap = 1
    kc.white = -1
    kc.indent = 1
    kc.rotate = 0
    kc.columns = 2
    kc.offset_x = 0
    kc.offset_y = 0
    kc.dev_dpi = 160
    kc.dev_width = 600
    kc.dev_height = 800
    kc.page_width = 600
    kc.page_height = 800
    kc.straighten = 0
    kc.justification = -1
    kc.read_max_width = 3000
    kc.read_max_height = 4000
    kc.writing_direction = 0
    -- number values
    kc.zoom = 1.0
    kc.margin = 0.06
    kc.quality = 1.0
    kc.contrast = 1.0
    kc.defect_size = 1.0
    kc.line_spacing = 1.2
    kc.word_spacing = -1
    kc.shrink_factor = 0.9
    -- states
    kc.precache = 0
    kc.debug = 0
    kc.cjkchar = 0
    -- struct
    kc.bbox = ffi.new("BBox", {0.0, 0.0, 0.0, 0.0})
    -- pointers
    kc.rboxa = nil
    kc.rnai = nil
    kc.nboxa = nil
    kc.nnai = nil
    kc.language = nil
    -- 1. in page reflowing context,
    --  `src` is the source page image fed into k2pdfopt, and `dst` is the reflowed
    --  page image. They usually have different page sizes.
    -- 2. in page optimization context,
    --  `src` is the source page image fed into k2pdfopt, and `dst` is the
    --  de-watermarked page image. They have the same page size.
    -- 3. in page segmentation context,
    --  `src` is the source page image fed into leptonica, and `dst` is the
    --  text block mask. They usually have different page sizes (the mask will be
    --  scaled down to half width and height).
    -- 4. in OCR context,
    --  `src` is an image of a word to be OCRed fed into k2pdfopt, and `dst` is unused.
    -- 5. in page cropping context,
    --  `src` is the source page image fed into k2pdfopt, and `dst` is unused.
    -- 6. in words boxing context,
    --  `src` is the source page image fed into k2pdfopt, and `dst` is unused.
    -- 7. in page drawing context,
    --  `src` is the source page image fed into leptonica, and `dst` is unused.
    k2pdfopt.bmp_init(kc.src)
    k2pdfopt.bmp_init(kc.dst)
    -- only used in words boxing context
    k2pdfopt.wrectmaps_init(kc.rectmaps)

    return kc
end

function KOPTContext.totable(kc)
    local context = {}
    -- version
    context.__version__ = __VERSION__
    -- integer values
    context.trim = kc.trim
    context.wrap = kc.wrap
    context.white = kc.white
    context.indent = kc.indent
    context.rotate = kc.rotate
    context.columns = kc.columns
    context.offset_x = kc.offset_x
    context.offset_y = kc.offset_y
    context.dev_dpi = kc.dev_dpi
    context.dev_width = kc.dev_width
    context.dev_height = kc.dev_height
    context.page_width = kc.page_width
    context.page_height = kc.page_height
    context.straighten = kc.straighten
    context.justification = kc.justification
    context.read_max_width = kc.read_max_width
    context.read_max_height = kc.read_max_height
    context.writing_direction = kc.writing_direction
    -- number values
    context.zoom = kc.zoom
    context.margin = kc.margin
    context.quality = kc.quality
    context.contrast = kc.contrast
    context.defect_size = kc.defect_size
    context.line_spacing = kc.line_spacing
    context.word_spacing = kc.word_spacing
    context.shrink_factor = kc.shrink_factor
    -- states
    context.precache = kc.precache
    context.debug = kc.debug
    context.cjkchar = kc.cjkchar
    -- struct
    context.bbox = ffi.string(kc.bbox, ffi.sizeof(kc.bbox))
    -- pointers
    if kc.rboxa ~= nil and kc.rboxa.n > 0 then
        context.rboxa = {
            n = kc.rboxa.n,
            box = {}
        }
        for i=0, kc.rboxa.n - 1 do
            table.insert(context.rboxa.box,
                    ffi.string(kc.rboxa.box[i], ffi.sizeof("BOX")))
        end
    end
    if kc.rnai ~= nil and kc.rnai.n > 0 then
        context.rnai = {
            n = kc.rnai.n,
            array = ffi.string(kc.rnai.array, ffi.sizeof("float")*kc.rnai.n)
        }
    end
    if kc.nboxa ~= nil and kc.nboxa.n > 0 then
        context.nboxa = {
            n = kc.nboxa.n,
            box = {}
        }
        for i=0, kc.nboxa.n - 1 do
            table.insert(context.nboxa.box,
                    ffi.string(kc.nboxa.box[i], ffi.sizeof("BOX")))
        end
    end
    if kc.nnai ~= nil and kc.nnai.n > 0 then
        context.nnai = {
            n = kc.nnai.n,
            array = ffi.string(kc.nnai.array, ffi.sizeof("float")*kc.nnai.n)
        }
    end
    if kc.language ~= nil then
        context.language = ffi.string(kc.language)
    end
    -- bmp structs
    context.src = ffi.string(kc.src, ffi.sizeof(kc.src))
    if kc.src.size_allocated > 0 then
        context.src_data = ffi.string(kc.src.data, kc.src.size_allocated)
    else
        context.src_data = ""
    end
    context.dst = ffi.string(kc.dst, ffi.sizeof(kc.dst))
    if kc.dst.size_allocated > 0 then
        context.dst_data = ffi.string(kc.dst.data, kc.dst.size_allocated)
    else
        context.dst_data = ""
    end
    -- rectmaps struct
    context.rectmaps = {
        n = kc.rectmaps.n,
        na = kc.rectmaps.n,
        wrectmap = ffi.string(kc.rectmaps.wrectmap,
                ffi.sizeof("WRECTMAP")*kc.rectmaps.n)
    }

    return context
end

function KOPTContext.fromtable(context)
    -- check version first
    if __VERSION__ ~= context.__version__ then
        error("mismatched versions")
    end
    local kc = kctype()
    -- integer values
    kc.trim = context.trim
    kc.wrap = context.wrap
    kc.white = context.white
    kc.indent = context.indent
    kc.rotate = context.rotate
    kc.columns = context.columns
    kc.offset_x = context.offset_x
    kc.offset_y = context.offset_y
    kc.dev_dpi = context.dev_dpi
    kc.dev_width = context.dev_width
    kc.dev_height = context.dev_height
    kc.page_width = context.page_width
    kc.page_height = context.page_height
    kc.straighten = context.straighten
    kc.justification = context.justification
    kc.read_max_width = context.read_max_width
    kc.read_max_height = context.read_max_height
    kc.writing_direction = context.writing_direction
    -- number values
    kc.zoom = context.zoom
    kc.margin = context.margin
    kc.quality = context.quality
    kc.contrast = context.contrast
    kc.defect_size = context.defect_size
    kc.line_spacing = context.line_spacing
    kc.word_spacing = context.word_spacing
    kc.shrink_factor = context.shrink_factor
    -- states
    kc.precache = context.precache
    kc.debug = context.debug
    kc.cjkchar = context.cjkchar
    -- struct
    if context.bbox ~= "" then
        ffi.copy(kc.bbox, context.bbox, ffi.sizeof(kc.bbox))
    end
    -- pointers
    if context.rboxa and context.rboxa.n > 0 then
        kc.rboxa = leptonica.boxaCreate(context.rboxa.n)
        for i=0, context.rboxa.n - 1 do
            leptonica.boxaAddBox(kc.rboxa, ffi.new("BOX[1]"), C.L_COPY)
            ffi.copy(kc.rboxa.box[i], context.rboxa.box[i+1], ffi.sizeof("BOX"))
        end
    else
        kc.rboxa = nil
    end
    if context.rnai and context.rnai.n > 0 then
        kc.rnai = leptonica.numaCreateFromFArray(ffi.cast("float*",
                context.rnai.array), context.rnai.n, C.L_COPY)
    end
    if context.nboxa and context.nboxa.n > 0 then
        kc.nboxa = leptonica.boxaCreate(context.nboxa.n)
        for i=0, context.nboxa.n - 1 do
            leptonica.boxaAddBox(kc.nboxa, ffi.new("BOX[1]"), C.L_COPY)
            ffi.copy(kc.nboxa.box[i], context.nboxa.box[i+1], ffi.sizeof("BOX"))
        end
    else
        kc.nboxa = nil
    end
    if context.nnai and context.nnai.n > 0 then
        kc.nnai = leptonica.numaCreateFromFArray(ffi.cast("float*",
                context.nnai.array), context.nnai.n, C.L_COPY)
    end
    if context.language then
        kc:setLanguage(context.language)
    end

    k2pdfopt.bmp_init(kc.src)
    ffi.copy(kc.src, context.src, ffi.sizeof(kc.src))
    if context.src_data ~= "" then
        kc.src.data = C.malloc(#context.src_data)
        ffi.copy(kc.src.data, context.src_data, #context.src_data)
    else
        kc.src.data = nil
    end
    k2pdfopt.bmp_init(kc.dst)
    ffi.copy(kc.dst, context.dst, ffi.sizeof(kc.dst))
    if context.dst_data ~= "" then
        kc.dst.data = C.malloc(#context.dst_data)
        ffi.copy(kc.dst.data, context.dst_data, #context.dst_data)
    else
        kc.dst.data = nil
    end
    k2pdfopt.wrectmaps_init(kc.rectmaps)
    kc.rectmaps.n = context.rectmaps.n
    kc.rectmaps.na = context.rectmaps.n
    if context.rectmaps.wrectmap ~= "" then
        kc.rectmaps.wrectmap = C.malloc(#context.rectmaps.wrectmap)
        ffi.copy(kc.rectmaps.wrectmap,
                context.rectmaps.wrectmap, #context.rectmaps.wrectmap)
    else
        kc.rectmaps.wrectmap = nil
    end

    return kc
end

return KOPTContext
