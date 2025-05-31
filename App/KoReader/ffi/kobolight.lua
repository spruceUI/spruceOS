local ffi = require("ffi")
local bor = bit.bor
local C = ffi.C

-- for closing on garbage collection, we need a pointer or aggregate
-- cdata object (not a plain "int"). So we encapsulate in a struct.
ffi.cdef[[
typedef struct light_fd { int ld; } light_fd;
]]

-- for ioctl header definition:
require("ffi/posix_h")

local kobolight = {}
local kobolight_mt = {__index={}}

function kobolight_mt.__index:close()
	-- this is redundant to garbage collection of the
	-- whole object and not strictly needed.
	-- it allows to force-close immediately, though.
	if self.light_fd and self.light_fd.ld ~= -1 then
		C.close(self.light_fd.ld)
		self.light_fd.ld = -1
	end
end

function kobolight_mt.__index:setBrightness(brightness)
	assert(brightness >= 0 and brightness <= 100,
		"Wrong brightness value given!")

	assert(C.ioctl(self.light_fd.ld, 241, ffi.cast("int", brightness)) == 0,
		"cannot change brightess value")
end

function kobolight.open(device)
	local light = {
		light_fd = nil,
	}

	local ld = C.open(device or "/dev/ntx_io", bor(C.O_RDONLY, C.O_NONBLOCK, C.O_CLOEXEC))
	assert(ld ~= -1, "cannot open ntx_io character device")
	light.light_fd = ffi.gc(
		ffi.new("light_fd", ld),
		function (light_fd) C.close(light_fd.ld) end
	)

	setmetatable(light, kobolight_mt)
	return light
end

return kobolight
