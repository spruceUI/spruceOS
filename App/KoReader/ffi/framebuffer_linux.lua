local ffi = require("ffi")
local bit = require("bit")
local BB = require("ffi/blitbuffer")
local C = ffi.C

require("ffi/linux_fb_h")
require("ffi/posix_h")

-- This is common across all mxcfb-like platforms.
local GRAYSCALE_8BIT = 0x1
local GRAYSCALE_8BIT_INVERTED = 0x2

local framebuffer = {
    device_node = "/dev/fb0",
    fd = -1,
    fb_size = nil,
    fb_bpp = nil,
    fb_rota = nil,
    data = nil,

    _finfo = nil,
    _vinfo = nil,
    _forced_rotation = false, -- true if painting, and HW rotation is actually forced now
}

--[[

The raw framebuffer memory is managed through Blitbuffer. When creating the
Blitbuffer, we bind it to a framebuffer memory size of `vinfo.yres *
finfo.line_length` and assuming the FB is laid out in portrait mode by default.

E-ink fb drivers are frequently broken, so we make only minimum assumptions
about correctness of the information reported, namely the following are crucial:

* vinfo.bits_per_pixel: Size of each pixel, for example, 16bits, 32bits, etc.
* finfo.line_length: Size (in bytes) of each row for the framebuffer.
                     Should be >= `vinfo.xres_virtual * vinfo.bits_per_pixel / 8`.
* vinfo.xres: Number of pixels in one row on physical screen, i.e. physical screen width
* vinfo.yres: Number of rows of the physical screen, i.e. physical screen height

The following don't concern us and we can survive if the values are bogus:

* finfo.smem_len: Size of the actual framebuffer memory provided by the kernel. We'll usually map
                  less than this (just finfo.line_length * vinfo.yres) to keep things on the safer side.
* vinfo.xres_virtual: Number of pixels in one row on scrollable virtual screen, for fb_pan_display.
                      Should be `vinfo.xres_virtual` >= `vinfo.xres`.
* vinfo.yres_virtual: Number of pixels in one column on scrollable virtual screen, for fb_pan_display.
                      Should be `vinfo.yres_virtual` >= `vinfo.yres`.
--]]

function framebuffer:init()
    self._finfo = ffi.new("struct fb_fix_screeninfo")
    self._vinfo = ffi.new("struct fb_var_screeninfo")
    self.fd = C.open(self.device_node, bit.bor(C.O_RDWR, C.O_CLOEXEC))
    assert(self.fd ~= -1, "cannot open framebuffer")
    self:reinit()
    framebuffer.parent.init(self)
    -- if force rotation is on with no default, the value from parent is a bogus preset, so ask the OS directly.
    if self.forced_rotation and not self.forced_rotation.default then
      local r = self:getHWRotation()
      local v = self:getCanonicalRotationMode(r)
      self.debug("Initializing 'native' rotation mode - OS reported ", r, "which maps to canonical", v)
      self.native_rotation_mode = v
      self.cur_rotation_mode = v
    end
end

-- Frontend driver should override this if they need to apply kludges on vinfo/finfo
function framebuffer:fbinfoOverride(finfo, vinfo)
end

-- Align FB size up to 4KB boundary, as device driver may provide direct mmio handler and not standard physmem mmap that does align kernel side.
-- We always track fb.fb_size unaligned, so as to have correct account of where the screen *really* ends.
local function PAGE_ALIGN(size)
    return bit.band(size + 4095, -4096)
end

function framebuffer:reinit()
    local finfo = self._finfo
    local vinfo = self._vinfo

    -- Unmap early, before fb_size gets overriden
    self:close(true)

    -- Get screen information
    assert(C.ioctl(self.fd, C.FBIOGET_FSCREENINFO, finfo) == 0, "cannot get fixed screen info")
    assert(C.ioctl(self.fd, C.FBIOGET_VSCREENINFO, vinfo) == 0, "cannot get variable screen info")

    -- Apply frontend kludges (color lux, very old eink...)
    self:fbinfoOverride(finfo, vinfo)

    assert(finfo.type == C.FB_TYPE_PACKED_PIXELS, "video type not supported")
    assert(vinfo.xres > 0 and vinfo.yres > 0, "invalid framebuffer resolution")

    -- We can forgo all messy fb detection logic by simply assuming only f.line_length and v.yres are valid,
    -- because if they aren't, the world would be on fire no matter what sooner or later.
    self.fb_size = finfo.line_length * vinfo.yres

    local bpp = vinfo.bits_per_pixel
    local stride_pixels = bit.lshift(finfo.line_length, 3)
    assert(stride_pixels % bpp == 0, "line_length doesn't end at pixel boundary")
    stride_pixels = stride_pixels / bpp

    self.debug("FB info (post fixup)", {
          fb_size = self.fb_size,
          xres = vinfo.xres,
          yres = vinfo.yres,
          xoffset = vinfo.xoffset,
          yoffset = vinfo.yoffset,
          bpp = bpp,
          xres_virtual = vinfo.xres,
          yres_virtual = vinfo.yres,
          line_length = finfo.line_length,
          stride_pixels = stride_pixels,
          smem_len = finfo.smem_len,
          type = finfo.type,
          mmio_len = finfo.mmio_len,
          rotate = vinfo.rotate,
          width_mm = vinfo.width,
          height_mm = vinfo.height,
    })

    -- Make sure we never try to map a larger memory region than the fb reports
    -- @warning Feel free to remove this check if it burns. There are chinese things out there that even happily report smem as 0x1000 and such.
    assert(self.fb_size <= finfo.smem_len or finfo.smem <= 0x1000, "computed fb memory region too large")

    -- @warning The assumption here is that mapping less than whatever reported (but aligned up to a page size) is always ok to do.
    self.data = C.mmap(nil,
                           PAGE_ALIGN(self.fb_size),
                           bit.bor(C.PROT_READ, C.PROT_WRITE),
                           C.MAP_SHARED,
                           self.fd,
                           0)
    assert(tonumber(ffi.cast("intptr_t", self.data)) ~= C.MAP_FAILED,
           "can not mmap() framebuffer, yres or line_length are probably wrong")
    self.debug("FB mapped at", self.data, "of", PAGE_ALIGN(self.fb_size), "bytes")

    -- @warning Don't ever cache self.bb, as we may replace it at any time later due to HW rotation causing fb reinit.
    self.bb = BB.new(vinfo.xres, vinfo.yres, BB["TYPE_BB"..bpp] or BB["TYPE_BBRGB"..bpp], self.data, finfo.line_length, stride_pixels)

    -- Make accessing the bitdepth easier, because we might want to know we're running on Kobo's quirky 16bpp mode later...
    self.fb_bpp = bpp

    -- Same for the current hardware rotation, it's potentially useful info on the Kobo Forma
    self.fb_rota = vinfo.rotate

    if ffi.string(finfo.id, 7) == "eink_fb" then
        -- classic eink framebuffer driver has grayscale values inverted (i.e. 0xF = black, 0 = white)
        -- technically a device quirk, but hopefuly generic enough to warrant being here
        self.bb:invert()
    end

    self.screen_size = self:getRawSize()
    self.bb:fill(BB.COLOR_WHITE)
end


function framebuffer:setHWNightmode(toggle)
    -- On some devices, the fb driver does some funky post-processing with the values passed by userland...
    -- This is catastrophically bad when this affects the rotate flag, so, don't do anything on those ;).
    if not self.device:canModifyFBInfo() then
        return
    end

    -- Only makes sense @ 8bpp
    if self.fb_bpp ~= 8 then
        return
    end

    -- And on devices with the actual capability.
    if not self.device:canHWInvert() then
        return
    end

    local vinfo = self._vinfo
    -- Just flip the grayscale flag.
    -- This shouldn't affect *anything* (layout-wise), which is why we don't touch the mmap or anything else, really.
    vinfo.grayscale = toggle and GRAYSCALE_8BIT_INVERTED or GRAYSCALE_8BIT
    assert(C.ioctl(self.fd, C.FBIOPUT_VSCREENINFO, vinfo) == 0,
           "cannot set variable screen info")
end

function framebuffer:getHWNightmode()
    if not self.device:canModifyFBInfo() then
        return false
    end

    -- Only makes sense @ 8bpp
    if self.fb_bpp ~= 8 then
        return false
    end

    -- And on devices with the actual capability.
    if not self.device:canHWInvert() then
        return false
    end

    local vinfo = self._vinfo
    return vinfo.grayscale == GRAYSCALE_8BIT_INVERTED
end

function framebuffer:setHWRotation(mode)
    local vinfo = self._vinfo
    vinfo.rotate = self.forced_rotation and self.forced_rotation[mode+1] or mode
    assert(C.ioctl(self.fd, C.FBIOPUT_VSCREENINFO, vinfo) == 0,
           "cannot set variable screen info")
end

function framebuffer:getHWRotation()
    local vinfo = self._vinfo
    assert(C.ioctl(self.fd, C.FBIOGET_VSCREENINFO, vinfo) == 0,
           "cannot get variable screen info")
    return vinfo.rotate
end

-- If the device can stomach it (this feature is frontend opt-in) perform hardware rotations
-- FIXME: What about viewports? Do we need to revert back to SW rotation mode?
function framebuffer:setRotationMode(mode)
    if not self.forced_rotation then
        -- Use SW rotation modes instead
        return framebuffer.parent.setRotationMode(self, mode)
    end
    assert(not self._forced_rotation, "do not flip rotation modes mid-paint")
    self.debug("setRotationMode:", mode, "old:", self.cur_rotation_mode)
    if mode ~= self.cur_rotation_mode then
        -- Requested rotation has changed. Set the HW to it and then reinit FB to update dimensions, line width,
        -- as well as prod the driver via new mmap() as some do tie down rotation modes to each mapping.
        self.cur_rotation_mode = mode
        self:setHWRotation(mode)
        -- Remember the screen bb's invert flag, too
        local inverse = self.bb:getInverse()
        self:reinit()
        self.bb:setInverse(inverse)
        assert(self.forced_rotation, "reinit/fb hooks shouldn't flip hw rotation flags")
        if self.forced_rotation.restore then
            self:setHWRotation(self.native_rotation_mode)
        end
    end
end


-- (before paint hook)
-- If enabled, force desired FB rotation mode in hardware.
-- This is to be done right before we're going to paint into the framebuffer. Because some other process can set
-- different rotation at any time without us knowing, we have to assert our own rot mode every time we're about to paint.
-- Yes this is silly and prone to race conditions, but thats's just how linux FB is - rotation is an OS wide flag. Don't ask.
function framebuffer:beforePaint()
    if (not self._forced_rotation) and self.forced_rotation then
      self._forced_rotation = true
      self:setHWRotation(self.cur_rotation_mode)
    end
    framebuffer.parent.beforePaint(self)
end

-- (after paint hook)
-- If enabled, restore hardware rotation mode to what OS expects.
-- This must be called after paints and refresh are finished - we don't need to have the HW rotation set now, and other process wishing
-- to steal focus (can happen at any time) from us may assume rotation didn't change. For this occasion we should reset rotation back to
-- "OS wide" one we've seen initially so as to not confuse outside FB users. This isn't always necessary, hence the bool opt-in.
function framebuffer:afterPaint()
    if self._forced_rotation and self.forced_rotation and self.forced_rotation.every_paint and self.forced_rotation.restore then
        self:setHWRotation(self.native_rotation_mode)
    end
    self._forced_rotation = false
    framebuffer.parent.afterPaint(self)
end

function framebuffer:close(reinit)
    if self.bb ~= nil then
        self.bb:free()
        self.bb = nil
    end
    if self.data then
        C.munmap(self.data, PAGE_ALIGN(self.fb_size))
        self.data = nil
    end
    if not reinit and (self.fd ~= -1) then
        if self.forced_rotation then
            -- Always restore the OS one so that koreader sees it if restarting
            self:setHWRotation(self.native_rotation_mode)
        end
        C.close(self.fd)
        self.fd = -1
    end
end

return require("ffi/framebuffer"):extend(framebuffer)
