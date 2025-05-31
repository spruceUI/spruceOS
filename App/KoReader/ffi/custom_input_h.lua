local ffi = require("ffi")

-- Custom values we use for ev.type, ev.code & ev.value in Input and Device HAL implementations
-- NOTE: EV_SDL == 'S'
--       MSC_GYRO == 'G'

-- In particular, orientation constants, usable by Device implementations for platform-specific gyro translations.
-- (matches framebuffer constants, which matches Linux <input/fb.h> FB_ROTATE_* constants).
-- (i.e., this is how the device is *physically* oriented).
ffi.cdef[[
static const int EV_SDL = 83;

static const int MSC_GYRO = 71;

static const int DEVICE_ROTATED_UPRIGHT = 0;
static const int DEVICE_ROTATED_CLOCKWISE = 1;
static const int DEVICE_ROTATED_UPSIDE_DOWN = 2;
static const int DEVICE_ROTATED_COUNTER_CLOCKWISE = 3;
]]
