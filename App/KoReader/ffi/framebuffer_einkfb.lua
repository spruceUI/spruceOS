local ffi = require("ffi")
require("ffi/posix_h")
require("ffi/einkfb_h")
local C = ffi.C

local framebuffer = {}

local function einkfb_update(fb, refreshtype, x, y, w, h)
    x, y, w, h = fb.bb:getBoundedRect(x, y, w, h)
    x, y, w, h = fb.bb:getPhysicalRect(x, y, w, h)

    local refarea = ffi.new("struct update_area_t[1]")

    refarea[0].x1 = x or 0
    refarea[0].y1 = y or 0
    refarea[0].x2 = x + w
    refarea[0].y2 = y + h
    refarea[0].buffer = nil
    refarea[0].which_fx = refreshtype

    C.ioctl(fb.fd, C.FBIO_EINK_UPDATE_DISPLAY_AREA, refarea);
end

function framebuffer:refreshPartialImp(x, y, w, h)
    einkfb_update(self, C.fx_update_partial, x, y, w, h)
end

function framebuffer:refreshFullImp(x, y, w, h)
    einkfb_update(self, C.fx_update_full, x, y, w, h)
end

return require("ffi/framebuffer_linux"):extend(framebuffer)
