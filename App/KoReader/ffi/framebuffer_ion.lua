local ffi = require("ffi")
local bit = require("bit")
local BB = require("ffi/blitbuffer")
local C = ffi.C

require("ffi/linux_fb_h")
require("ffi/ion_kobo_h")
require("ffi/sunxi_kobo_h")
require("ffi/posix_h")

local framebuffer = {
    fb_node = "/dev/fb0",
    ion_node = "/dev/ion",
    disp_node = "/dev/disp",
    ion_fd = -1,
    fd = -1,

    fb_size = nil,
    fb_bpp = 8,
    fb_rota = C.FB_ROTATE_UR,

    data = nil,

    alloc_size = nil,
    ion = nil,
    layer = nil,
    g2d_rota = nil,

    boot_rota = nil, -- MUST be specified by the caller: "native" panel rotation.

    _finfo = nil,
    _vinfo = nil,

    _just_rotated = nil,
}

--[[
This is roughly based on framebuffer_linux, and shares some of the logic with it.
--]]

-- Frontend driver should override this if they need to apply kludges on vinfo/finfo
function framebuffer:fbinfoOverride(finfo, vinfo)
end

-- This, on the other hand, is a standard sunxi fixup we apply unconditionally
local function fbinfo_sunxi_fixup(finfo, vinfo)
    -- Handle Portrait/Landscape swaps
    local xres = vinfo.xres
    local yres = vinfo.yres
    if bit.band(vinfo.rotate, 1) == 1 then
        -- Odd, Landscape
        vinfo.xres = math.max(xres, yres)
        vinfo.yres = math.min(xres, yres)
    else
        -- Even, Portrait
        vinfo.xres = math.min(xres, yres)
        vinfo.yres = math.max(xres, yres)
    end

    -- We need a dumb unpadded pitch...
    vinfo.xres_virtual = vinfo.xres
    vinfo.yres_virtual = vinfo.yres

    -- Make it grayscale...
    vinfo.bits_per_pixel = 8
    vinfo.grayscale      = 1

    -- Stride & buffer size
    finfo.line_length = bit.rshift(vinfo.xres_virtual * vinfo.bits_per_pixel, 3)
    finfo.smem_len = finfo.line_length * vinfo.yres_virtual
end

-- And this to setup the insanity of the sunxi disp2 layer...
local function setupSunxiLayer(layer, finfo, vinfo)
    -- disp_layer_info2
    layer.info.mode        = C.LAYER_MODE_BUFFER
    layer.info.zorder      = 0
    -- NOTE: Ignore pixel alpha.
    --       We actually *do* handle alpha sanely, so,
    --       if we were actually using an RGB32 fb, we might want to tweak that & pre_multiply...
    layer.info.alpha_mode  = 1
    layer.info.alpha_value = 0xFF

    -- disp_rect
    layer.info.screen_win.x      = 0
    layer.info.screen_win.y      = 0
    layer.info.screen_win.width  = vinfo.xres
    layer.info.screen_win.height = vinfo.yres

    layer.info.b_trd_out    = false
    layer.info.out_trd_mode = 0

    -- disp_fb_info2
    -- NOTE: fd & y8_fd are handled in framebuffer:init().
    --       And they are *explicitly* set to 0 and not -1 when unused,
    --       because that's what the disp code (mostly) expects (*sigh*).

    -- disp_rectsz
    -- NOTE: Used in conjunction with align below.
    --       We obviously only have a single buffer, because we're not a 3D display...
    layer.info.fb.size[0].width  = vinfo.xres_virtual
    layer.info.fb.size[0].height = vinfo.yres_virtual
    layer.info.fb.size[1].width  = 0
    layer.info.fb.size[1].height = 0
    layer.info.fb.size[2].width  = 0
    layer.info.fb.size[2].height = 0

    -- NOTE: Used to compute the scanline pitch in bytes (e.g., pitch = ALIGN(scanline_pixels * components, align).
    --       This is set to 2 by Nickel, but we appear to go by without it just fine with a Y8 fb fd...
    layer.info.fb.align[0]      = 0
    layer.info.fb.align[1]      = 0
    layer.info.fb.align[2]      = 0
    layer.info.fb.format        = C.DISP_FORMAT_8BIT_GRAY
    layer.info.fb.color_space   = C.DISP_GBR_F  -- Full-range RGB
    layer.info.fb.trd_right_fd  = 0
    layer.info.fb.pre_multiply  = true  -- Because we're using global alpha, I guess?
    layer.info.fb.crop.x        = 0
    layer.info.fb.crop.y        = 0
    -- Don't ask me why this needs to be shifted 32 bits to the left... ¯\_(ツ)_/¯
    -- Although it apparently behaves without it, too...
    layer.info.fb.crop.width    = bit.lshift(ffi.cast("uint64_t", vinfo.xres), 32)
    layer.info.fb.crop.height   = bit.lshift(ffi.cast("uint64_t", vinfo.yres), 32)
    layer.info.fb.flags         = C.DISP_BF_NORMAL
    layer.info.fb.scan          = C.DISP_SCAN_PROGRESSIVE
    layer.info.fb.eotf          = C.DISP_EOTF_GAMMA22  -- SDR
    layer.info.fb.depth         = 0
    layer.info.fb.fbd_en        = 0
    layer.info.fb.metadata_fd   = 0
    layer.info.fb.metadata_size = 0
    layer.info.fb.metadata_flag = 0

    layer.info.id = 0

    -- disp_atw_info
    layer.info.atw.used   = false
    layer.info.atw.mode   = 0
    layer.info.atw.b_row  = 0
    layer.info.atw.b_col  = 0
    layer.info.atw.cof_fd = 0

    layer.enable   = true
    layer.channel  = 0
    -- NOTE: Nickel uses layer 0, pickel layer 1.
    layer.layer_id = 1
end

-- Compute the G2D rotation angle for the current rotation
function framebuffer:_computeG2DAngle()
    -- c.f., FBInk's kobo_sunxi_fb_fixup
    self.g2d_rota[0] = bit.band(self.boot_rota - self._vinfo.rotate, 3) * 90
end

-- We request PAGE-aligned addresses from ION, *and* PAGE-aligned allocation sizes.
local function PAGE_ALIGN(size)
    return bit.band(size + 4095, -4096)
end

function framebuffer:init()
    -- We'll start by the usual poking at fb0, as it's the only way to get accurate screen dimension information...
    self._finfo = ffi.new("struct fb_fix_screeninfo")
    self._vinfo = ffi.new("struct fb_var_screeninfo")

    local fbfd = C.open(self.fb_node, bit.bor(C.O_RDONLY, C.O_NONBLOCK, C.O_CLOEXEC))
    assert(fbfd ~= -1, "cannot open framebuffer")

    -- Get screen information
    assert(C.ioctl(fbfd, C.FBIOGET_FSCREENINFO, self._finfo) == 0, "cannot get fixed screen info")
    assert(C.ioctl(fbfd, C.FBIOGET_VSCREENINFO, self._vinfo) == 0, "cannot get variable screen info")

    -- ... and we're actually done with the framebuffer device ;).
    C.close(fbfd)

    -- We enforce startup @ UR, the actual value returned by the ioctl is meaningless on sunxi.
    self._vinfo.rotate = C.FB_ROTATE_UR

    -- Apply mandatory kludges
    fbinfo_sunxi_fixup(self._finfo, self._vinfo)
    -- Apply frontend kludges
    self:fbinfoOverride(self._finfo, self._vinfo)

    assert(self._finfo.type == C.FB_TYPE_PACKED_PIXELS, "video type not supported")
    assert(self._vinfo.xres > 0 and self._vinfo.yres > 0, "invalid framebuffer resolution")

    -- We'll map a screen's worth of memory
    self.fb_size = self._finfo.line_length * self._vinfo.yres_virtual

    local bpp = self._vinfo.bits_per_pixel
    local stride_pixels = bit.lshift(self._finfo.line_length, 3)
    assert(stride_pixels % bpp == 0, "line_length doesn't end at pixel boundary")
    stride_pixels = stride_pixels / bpp

    self.debug("FB info (post fixup)", {
          fb_size = self.fb_size,
          xres = self._vinfo.xres,
          yres = self._vinfo.yres,
          bpp = bpp,
          xres_virtual = self._vinfo.xres,
          yres_virtual = self._vinfo.yres,
          line_length = self._finfo.line_length,
          stride_pixels = stride_pixels,
          smem_len = self._finfo.smem_len,
          type = self._finfo.type,
          rotate = self._vinfo.rotate,
          width_mm = self._vinfo.width,
          height_mm = self._vinfo.height,
    })

    -- Make sure we never try to map a larger memory region than the fb reports
    assert(self.fb_size <= self._finfo.smem_len or self._finfo.smem <= 0x1000, "computed fb memory region too large")

    -- And now we can start dealing with ION proper...
    self.ion = ffi.new("struct ion_fd_data")
    self.ion.fd = -1

    -- Start by registering as an ION client
    self.ion_fd = C.open(self.ion_node, bit.bor(C.O_RDONLY, C.O_NONBLOCK, C.O_CLOEXEC))
    assert(self.ion_fd ~= -1, "cannot open ION handle")

    -- Then request a page-aligned carveout mapping large enough to fit our screen
    self.alloc_size = PAGE_ALIGN(self._finfo.smem_len)
    local alloc = ffi.new("struct ion_allocation_data")
    alloc.len = self.alloc_size
    alloc.align = 4096
    alloc.heap_id_mask = C.ION_HEAP_MASK_CARVEOUT
    assert(C.ioctl(self.ion_fd, C.ION_IOC_ALLOC, alloc) == 0, "cannot allocate ION buffer")

    -- Request a dmabuff handle that we can share & mmap for that alloc
    self.ion.handle = alloc.handle
    assert(C.ioctl(self.ion_fd, C.ION_IOC_MAP, self.ion) == 0, "cannot get dmabuff handle from ION")

    -- And we're back in familiar territory: mmap it!
    self.data = C.mmap(nil, self.alloc_size, bit.bor(C.PROT_READ, C.PROT_WRITE), C.MAP_SHARED, self.ion.fd, 0)
    assert(tonumber(ffi.cast("intptr_t", self.data)) ~= C.MAP_FAILED, "can not mmap() ION buffer")

    -- And point our screen BB at it
    -- @warning Don't ever cache self.bb, as we may replace it at any time later due to rotation.
    self.bb = BB.new(self._vinfo.xres, self._vinfo.yres, BB["TYPE_BB"..bpp] or BB["TYPE_BBRGB"..bpp], self.data, self._finfo.line_length, stride_pixels)

    -- Make a few vInfo fields easier to access
    self.fb_bpp = bpp
    self.fb_rota = self._vinfo.rotate

    -- And finally, register as a DISP client, too
    self.fd = C.open(self.disp_node, bit.bor(C.O_RDONLY, C.O_NONBLOCK, C.O_CLOEXEC))
    assert(self.fd ~= -1, "cannot open DISP handle")

    -- Setup the insanity that is the sunxi disp2 layer...
    self.layer = ffi.new("struct disp_layer_config2")
    setupSunxiLayer(self.layer, self._finfo, self._vinfo)

    -- And update our layer config to use our dmabuff fd, as a grayscale buffer.
    self.layer.info.fb.fd    = 0
    self.layer.info.fb.y8_fd = self.ion.fd

    -- Setup the G2D rotation angle
    self.g2d_rota = ffi.new("uint32_t[1]")
    self:_computeG2DAngle()

    -- And we're cooking with gas!
    self.screen_size = self:getRawSize()
    self.bb:fill(BB.COLOR_WHITE)

    framebuffer.parent.init(self)

    -- fbdepth ensures we always start UR
    self.native_rotation_mode = C.FB_ROTATE_UR
    self.cur_rotation_mode = C.FB_ROTATE_UR
end

function framebuffer:reinit()
    -- The actual ION buffer doesn't need to change, as its size won't, since it's unpadded.
    -- Which means we just need to update the Screen's BB layout ;).
    if self.bb ~= nil then
        -- Highly pedantic: it's mmap-backed, so this is a NOP.
        self.bb:free()
        self.bb = nil
    end

    -- Reapply the fbinfo kludges, as they do depend on layout
    fbinfo_sunxi_fixup(self._finfo, self._vinfo)
    self:fbinfoOverride(self._finfo, self._vinfo)

    -- Update the layer's layout, too
    setupSunxiLayer(self.layer, self._finfo, self._vinfo)

    -- Update the G2D rotation angle
    self:_computeG2DAngle()

    -- And recreate our Screen BB in the new layout
    local bpp = self._vinfo.bits_per_pixel
    local stride_pixels = bit.lshift(self._finfo.line_length, 3)
    assert(stride_pixels % bpp == 0, "line_length doesn't end at pixel boundary")
    stride_pixels = stride_pixels / bpp

    self.bb = BB.new(self._vinfo.xres, self._vinfo.yres, BB["TYPE_BB"..bpp] or BB["TYPE_BBRGB"..bpp], self.data, self._finfo.line_length, stride_pixels)
    self.fb_rota = self._vinfo.rotate

    self.screen_size = self:getRawSize()
    self.bb:fill(BB.COLOR_WHITE)

    -- Ask framebuffer_sunxi to make sure the next update is full-screen, in order to avoid layer blending glitches...
    -- (e.g., CRe loading bar, a very small refresh region, into the actual full-screen page refresh at the end).
    -- NOTE: This cannot be reproduced with Wi-Fi enabled, in yet another weird EPDC power management quirk...
    -- NOTE: It will *not* prevent tripping the "refresh in staggered quadrants" issue on the actual page refresh,
    --       but at least the actual page content will not be garbled ;).
    --       (Fun fact: much like the above, the staggered refresh thing doesn't happen with Wi-Fi enabled...)
    -- The good news is that this scenario doesn't really happen anymore with CRe progressive rendering,
    -- as a rotation is now very unlikely to require a progress bar, so the first refresh is natively full-screen already ;).
    self._just_rotated = true
end

-- The actual HW fb state is meaningless, just set/get our own internal state
function framebuffer:setHWRotation(mode)
    self._vinfo.rotate = mode

    -- Tell FBInk about it, so the OTA prints follow suit
    C.setenv("FBINK_FORCE_ROTA", tostring(mode), 1)
end

function framebuffer:getHWRotation()
    return self._vinfo.rotate
end

-- Handle "HW" rotation, by simply recreating the buffer in the desired layout,
-- and updating the G2D rota angle.
function framebuffer:setRotationMode(mode)
    self.debug("setRotationMode:", mode, "old:", self.cur_rotation_mode)
    if mode ~= self.cur_rotation_mode then
        -- Requested rotation has changed. Reinit our Screen BB to follow the new layout.
        self.cur_rotation_mode = mode
        self:setHWRotation(mode)
        -- Remember the screen bb's invert flag, too
        local inverse = self.bb:getInverse()
        self:reinit()
        self.bb:setInverse(inverse)
    end
end

function framebuffer:close()
    if self.bb ~= nil then
        self.bb:free()
        self.bb = nil
    end
    if self.data then
        C.munmap(self.data, self.alloc_size)
        self.data = nil
        self.alloc_size = nil
    end
    if self.ion and self.ion.fd ~= -1 then
       C.close(self.ion.fd)
       self.ion.fd = -1
    end
    if self.ion and self.ion.handle ~= 0 then
        local handle = ffi.new("struct ion_handle_data")
        handle.handle = self.ion.handle
        assert(C.ioctl(self.ion_fd, C.ION_IOC_FREE, handle) == 0, "cannot release ION buffer")
        self.ion.handle = 0
    end
    if self.ion_fd ~= -1 then
        C.close(self.ion_fd)
        self.ion_fd = -1
    end
    if self.fd ~= -1 then
        C.close(self.fd)
        self.fd = -1
    end
end

return require("ffi/framebuffer"):extend(framebuffer)
