--[[--
Framebuffer API.

This will be extended by implementations of this API.

@module ffi.framebuffer
--]]

local Blitbuffer = require("ffi/blitbuffer")

local fb = {
    device = nil, -- points to a device object
    debug = function(...) --[[ NOP ]] end,

    bb = nil, -- should be set by implementations
    full_bb = nil, -- will hold a reference to the full-size native buffer when a viewport is set
    viewport = nil,
    screen_size = nil,
    native_rotation_mode = nil,
    cur_rotation_mode = nil,
    blitbuffer_rotation_mode = nil,
    night_mode = false,
    hw_dithering = false, -- will be setup via setupDithering @ startup by reader.lua
    sw_dithering = false, -- will be setup via setupDithering @ startup by reader.lua
    swipe_animations = false, -- will be toggled at page turn by the frontend
    is_always_portrait = false, -- true = SW flip landscape into portrait (historically a bit of misnomer)
    forced_rotation = nil, --[[{
        -- canonically the order below - but frontend may specify their own mapping
        fb.DEVICE_ROTATED_UPRIGHT,
        fb.DEVICE_ROTATED_CLOCKWISE,
        fb.DEVICE_ROTATED_UPSIDE_DOWN,
        fb.DEVICE_ROTATED_COUNTER_CLOCKWISE,
        restore = false, -- true if hw rot mode is to be restored after painting, see framebuffer_linux:afterPaint()
        default = nil, -- if not nil, use this as default rotation value (this one is canonical, not HW)
        every_paint = false, -- true if HW mode should be enforced for every paint batch
    },]]
    -- User-selectable WF aggressiveness.
    -- Lower level is the slowest and most conservative, increasing values trade speed for glitches and ghosting.
    wf_level = 0,
    wf_level_max = 0, -- Maximum supported value for wf_level.
    -- Whether the user (or a Device cap check) chose to disable MXCFB_WAIT_FOR_UPDATE_* ioctls.
    mxcfb_bypass_wait_for = false,
}

--[[
Canonical values for rotation modes:

0 for no rotation (i.e., Portrait),
1 for landscape with bottom on the right side of screen, etc.

           2
   +--------------+
   | +----------+ |
   | |          | |
   | | Freedom! | |
   | |          | |
   | |          | |
 3 | |          | | 1
   | |          | |
   | |          | |
   | +----------+ |
   |              |
   |              |
   +--------------+
          0

i.e., this matches <linux/fb.h> FB_ROTATE_* constants ;).

This corresponds to the user-facing *physical device* rotation (in 90° CW steps).

NOTE: The fact that we tend to make strong assumptions about UPRIGHT being a Portrait orientation
      is simply based on the fact that it currently matches the form-factor of our target platforms.
      But if you were to take a widescreen TV/monitor, its UPRIGHT orientation would be a Landscape one...

--]]
fb.DEVICE_ROTATED_UPRIGHT           = 0 -- UR, Portait
fb.DEVICE_ROTATED_CLOCKWISE         = 1 -- CW, Landscape
fb.DEVICE_ROTATED_UPSIDE_DOWN       = 2 -- UD, Inverted Portrait
fb.DEVICE_ROTATED_COUNTER_CLOCKWISE = 3 -- CCW, Inverted Landscape

--[[
Rotation modes are not guaranteed to be canonical however, as HW driver may interpret the value as CW or CCW, as well
as starting from elsewhere than portrait so in practice the values can be pretty much anything.
For such an occasion the frontend can provide custom mappings, or simply override the HW setter/getter/map function.
]]

-- Invert HW value to canonical one, needed to interpret the one given by OS.
-- Some devices may wish to override this if the mapping is not as simple as 1:1.
function fb:getCanonicalRotationMode(hw)
    for k,v in ipairs(self.forced_rotation) do
        if v == hw then
            return k-1
        end
    end
end

-- To be overridden. Returns the current FB rotation exactly as reported by hw
-- Pipe the result into getCanonicalRotationMode() if you want canonical (ie the koreader uses) result.
function fb:getHWRotation()
    return 0
end

-- To be overridden. Set HW rotation of the FB. Note that the argument is canonical value, ie this
-- call should do translation from forced_rotation[] table - or any other necessary dance to convert
-- canonical fb.DEVICE_ROTATED_ mode to HW reality.
function fb:setHWRotation(canon)
end

-- To be overriden. Enable nightmode globally by switching the grayscale fb vinfo flag.
-- Requires the canHWInvert device cap.
function fb:setHWNightmode(toggle)
end
-- To be overriden. Returns true if the grayscale flag is set to GRAYSCALE_8BIT_INVERTED on an 8bpp fb.
function fb:getHWNightmode()
    return false
end

-- Rotation modes may cause desync of rotation for touch translation, so frontend may need to override this
-- to provide a fixup.
function fb:getTouchRotation()
    -- The touch matrix stays the same for things like linuxfb so just output the rotation we're doing either hw or sw.
    -- But this may not be necessarily so with other backends.
    return self.cur_rotation_mode
end

local EMULATE_READER_DPI = tonumber(os.getenv("EMULATE_READER_DPI"))

function fb:extend(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o.parent = self
    return o
end

function fb:new(o)
    o = self:extend(o)
    if o.init then o:init() end
    return o
end

-- you can do the setup here, but remember to call this from implementations!
function fb:init()
    self.blitbuffer_rotation_mode = self.bb:getRotation()
    -- asking the framebuffer for orientation is error prone,
    -- so we do this simple heuristic (for now)
    self.screen_size = self:getRawSize()
    if self.screen_size.w > self.screen_size.h and self.is_always_portrait then
        self.screen_size.w, self.screen_size.h = self.screen_size.h, self.screen_size.w
        -- some framebuffers need to be rotated counter-clockwise (they start in landscape mode)
        io.write("FB: Enforcing portrait mode by doing an initial BB rotation\n")
        self.debug("FB: This prevents the use of blitting optimizations. This should instead be fixed on the device's side on startup.")
        self.bb:rotate(-90)
        self.blitbuffer_rotation_mode = self.bb:getRotation()
        assert(not self.forced_rotation, "If forced HW rotation is used, isAlwaysPortrait should not be set.")
    end
    self.native_rotation_mode = self.forced_rotation and self.forced_rotation.default or self.DEVICE_ROTATED_UPRIGHT
    self.cur_rotation_mode = self.native_rotation_mode
end

-- This method must be called just before drawing a sequence of blits into a framebuffer.
-- It's ok to spam it for each paint, drivers should ensure to become nop for subsequent calls until final afterPaint().
function fb:beforePaint()
end

-- This method must be called once we're done drawing all batched updates into a framebuffer, and *after* all the necessary fb:refresh* calls.
function fb:afterPaint()
end

-- the ...Imp methods may be overridden to implement refresh
function fb:refreshFullImp(x, y, w, h, d)
    -- the simplest form of refresh implements only this method.
    -- the others default to fall back to this.
end
function fb:refreshPartialImp(x, y, w, h, d)
    return self:refreshFullImp(x, y, w, h, d)
end
function fb:refreshNoMergePartialImp(x, y, w, h, d)
    return self:refreshPartialImp(x, y, w, h, d)
end
function fb:refreshFlashPartialImp(x, y, w, h, d)
    return self:refreshFullImp(x, y, w, h, d)
end
function fb:refreshUIImp(x, y, w, h, d)
    return self:refreshPartialImp(x, y, w, h, d)
end
function fb:refreshNoMergeUIImp(x, y, w, h, d)
    return self:refreshUIImp(x, y, w, h, d)
end
function fb:refreshFlashUIImp(x, y, w, h, d)
    return self:refreshFullImp(x, y, w, h, d)
end
function fb:refreshFastImp(x, y, w, h, d)
    return self:refreshPartialImp(x, y, w, h, d)
end
function fb:refreshA2Imp(x, y, w, h, d)
    return self:refreshFastImp(x, y, w, h, d)
end
function fb:refreshWaitForLastImp()
    -- default is NOP
end

-- these should not be overridden, they provide the external refresh API:
--- @note: x, y, w, h are *mandatory*, even for refreshFull! (UIManager guarantees it).
function fb:refreshFull(x, y, w, h, d)
    x, y, w, h = self:calculateRealCoordinates(x, y, w, h)
    return self:refreshFullImp(x, y, w, h, d)
end
function fb:refreshPartial(x, y, w, h, d)
    x, y, w, h = self:calculateRealCoordinates(x, y, w, h)
    return self:refreshPartialImp(x, y, w, h, d)
end
function fb:refreshNoMergePartial(x, y, w, h, d)
    x, y, w, h = self:calculateRealCoordinates(x, y, w, h)
    return self:refreshNoMergePartialImp(x, y, w, h, d)
end
function fb:refreshFlashPartial(x, y, w, h, d)
    x, y, w, h = self:calculateRealCoordinates(x, y, w, h)
    return self:refreshFlashPartialImp(x, y, w, h, d)
end
function fb:refreshUI(x, y, w, h, d)
    x, y, w, h = self:calculateRealCoordinates(x, y, w, h)
    return self:refreshUIImp(x, y, w, h, d)
end
function fb:refreshNoMergeUI(x, y, w, h, d)
    x, y, w, h = self:calculateRealCoordinates(x, y, w, h)
    return self:refreshNoMergeUIImp(x, y, w, h, d)
end
function fb:refreshFlashUI(x, y, w, h, d)
    x, y, w, h = self:calculateRealCoordinates(x, y, w, h)
    return self:refreshFlashUIImp(x, y, w, h, d)
end
function fb:refreshFast(x, y, w, h, d)
    x, y, w, h = self:calculateRealCoordinates(x, y, w, h)
    return self:refreshFastImp(x, y, w, h, d)
end
function fb:refreshA2(x, y, w, h, d)
    x, y, w, h = self:calculateRealCoordinates(x, y, w, h)
    return self:refreshA2Imp(x, y, w, h, d)
end
function fb:refreshWaitForLast()
    return self:refreshWaitForLastImp()
end

-- should be overridden to free resources
function fb:close()
end

-- you probably do not need to override any of the following functions:

--[[
set a rectangle that represents the area of the screen we are working on
--]]
function fb:setViewport(viewport)
    if viewport.x < 0 or viewport.x > self.screen_size.w
    or viewport.y < 0 or viewport.y > self.screen_size.h
    or viewport.w < 0 or viewport.x+viewport.w > self.screen_size.w
    or viewport.h < 0 or viewport.y+viewport.h > self.screen_size.h
    then
        error("fb:setViewport() bad viewport")
    end
    -- we might be switching the viewport on the fly, so don't overwrite self.full_bb
    if not self.full_bb then
        self.full_bb = self.bb
    end
    self.debug("fb:setViewport() setting viewport to",
               viewport.x, viewport.y,
               viewport.w, viewport.h)
    self.bb = self.full_bb:viewport(
        viewport.x, viewport.y,
        viewport.w, viewport.h)
    self.viewport = viewport
    self.full_bb:fill(Blitbuffer.COLOR_WHITE)
    -- We want the *viewport's* dimensions, as calculateRealCoordinates will adjust the coordinates later.
    self:refreshFull(0, 0, self:getWidth(), self:getHeight())
end

-- If there is a viewport in place, spit out adjusted coordinates for the native buffer that account for it
function fb:calculateRealCoordinates(x, y, w, h)
    if not self.viewport then return x, y, w, h end

    -- TODO: May need to implement refresh translations for HW rotate on broken drivers.
    --       For now those should just avoid using HW mode altogether.
    --[[
        we need to adapt the coordinates when we have a viewport.
        this adaptation depends on the rotation:

      0,0               fb.w
        +---+---------------------------+---+
        |   |v.y                     v.y|   |
        |v.x|                           |vx2|
        +---+---------------------------+---+
        |   |           v.w             |   |
        |   |                           |   |
        |   |                           |   |
        |   |v.h     (viewport)         |   |
        |   |                           |   | fb.h
        |   |                           |   |
        |   |                           |   |
        |   |                           |   |
        +---+---------------------------+---+
        |v.x|                           |vx2|
        |   |vy2                     vy2|   |
        +---+---------------------------+---+

        The viewport offset v.y/v.x only applies when rotation is 0 degrees.
        For other rotations (0,0 is in one of the other edges), we need to
        recalculate the offsets.
    --]]

    -- Ensure OOB coordinates do not allow requesting a refresh large enough to spill *outside* of the viewport...
    -- NOTE: This is done here, instead of in the public refresh*() methods (where we'd explicitly run it on the viewport bb),
    --       because implementations may prefer to bound to the *full* screen, instead of the viewport's dimensions,
    --       especially if an alignment constraint is at play...
    x, y, w, h = self.bb:getBoundedRect(x, y, w, h)

    local mode = self:getRotationMode()
    local vx2 = self.screen_size.w - (self.viewport.x + self.viewport.w)
    local vy2 = self.screen_size.h - (self.viewport.y + self.viewport.h)

    if mode == self.DEVICE_ROTATED_UPRIGHT then
        -- (0, 0) is at top left of screen
        x = x + self.viewport.x
        y = y + self.viewport.y
    elseif mode == self.DEVICE_ROTATED_CLOCKWISE then
        -- (0, 0) is at bottom left of screen
        x = x + vy2
        y = y + self.viewport.x
    elseif mode == self.DEVICE_ROTATED_UPSIDE_DOWN then
        -- (0, 0) is at bottom right of screen
        x = x + vx2
        y = y + vy2
    else -- self.DEVICE_ROTATED_COUNTER_CLOCKWISE
        -- (0, 0) is at top right of screen
        x = x + self.viewport.y
        y = y + vx2
    end

    return x, y, w, h
end

function fb:getRawSize()
    return {w = self.bb:getWidth(), h = self.bb:getHeight()}
end

function fb:getWidth()
    return self.bb:getWidth()
end

function fb:getHeight()
    return self.bb:getHeight()
end

function fb:getScreenWidth()
    return self.screen_size.w
end

function fb:getScreenHeight()
    return self.screen_size.h
end

function fb:getDPI()
    if self.dpi ~= nil then
        return self.dpi
    end

    self.dpi = EMULATE_READER_DPI

    if self.dpi == nil and self.device then
        self.dpi = self.device.display_dpi
    end

    if self.dpi == nil then
        self.dpi = 160
    end

    return self.dpi
end

function fb:clearDPI()
    self.dpi = nil
    -- Restore self.dpi to defaults
    self:getDPI()

    -- Clear the override flag
    self.dpi_override = nil
end

function fb:setDPI(dpi)
    -- If we passed a nil, reset to defaults and clear the override flag
    if not dpi then
        return self:clearDPI()
    end

    -- Nothing except having a real DPI override ("screen_dpi" reader setting non nil) set calls Device:setScreenDPI -> fb:setDPI
    self.dpi = dpi
    -- Remember that we're using an override for scaleBySize
    self.dpi_override = true
end

--[[--
Calculate pixel from density-independent pixel

@int dp density-independent pixel
@treturn int pixel
]]--
function fb:scaleByDPI(dp)
    -- Round up, to make sure we never end up with a zero
    return math.ceil(dp * self:getDPI() / 160)
end

function fb:scaleBySize(px)
    -- Larger screen needs larger scale
    local size_scale = math.min(self:getWidth(), self:getHeight()) / 600

    -- Unless the user has a DPI override set, DPI doesn't actually factor into the equation at all.
    local dpi_scale = size_scale
    if self.dpi_override then
        dpi_scale = self.dpi / 160
    end

    -- Round up, to make sure we never end up with a zero
    return math.ceil(px * (size_scale + dpi_scale) / 2)
end

function fb:getRotationMode()
    return self.cur_rotation_mode
end

--- This reflects how the screen *looks* like, not the screen layout relative to its native orientation...
function fb:getScreenMode()
    if self:getWidth() > self:getHeight() then
        return "landscape"
    else
        return "portrait"
    end
end

--- This reflects the current layout in terms of *rotation* modes
function fb:getScreenOrientation()
    if bit.band(self:getRotationMode(), 1) == 1 then
        -- LinuxFB constants, Landscapes are odds
        return "landscape"
    else
        -- And Portraits are even
        return "portrait"
    end
end

-- Configure desired rotation. By default, we setup the blitter to do rotations for us, but a subclass
-- may implement rotation via hardware (android with hasNativeRotation, linuxfb with forced_rotation).
function fb:setRotationMode(mode)
    -- This, on the other hand, is responsible for the internal *buffer* rotation,
    -- as such, it's inverted compared to the DEVICE_ROTATED_ constants; i.e., it's in 90° CCW steps).
    self.bb:rotateAbsolute(-90 * (mode - self.native_rotation_mode - self.blitbuffer_rotation_mode))
    if self.viewport then
        self.full_bb:setRotation(self.bb:getRotation())
    end
    self.cur_rotation_mode = mode
end

function fb:getWindowTitle()
    return self.window_title
end

function fb:setWindowTitle(new_title)
    if new_title and new_title ~= "" then
        self.window_title = new_title .. " - KOReader"
    else
        self.window_title = "KOReader"
    end
end

function fb:toggleNightMode()
    self.night_mode = not self.night_mode
    if self.device:canHWInvert() then
        -- If the device supports global inversion via the grayscale flag, do that.
        self:setHWNightmode(self.night_mode)
    else
        -- Only do SW inversion if the HW can't...
        self.bb:invert()
        if self.viewport then
            -- invert and blank out the full framebuffer when we are working on a viewport
            self.full_bb:setInverse(self.bb:getInverse())
            self.full_bb:fill(Blitbuffer.COLOR_WHITE)
        end
    end
end

function fb:toggleHWDithering(toggle)
    if toggle == true then
        self.hw_dithering = true
    elseif toggle == false then
        self.hw_dithering = false
    else
        self.hw_dithering = not self.hw_dithering
    end
end

function fb:toggleSWDithering(toggle)
    if toggle == true then
        self.sw_dithering = true
    elseif toggle == false then
        self.sw_dithering = false
    else
        self.sw_dithering = not self.sw_dithering
    end
end

function fb:setupDithering()
    -- Prefer HW dither to SW dither
    if self.device:canHWDither() then
        self.hw_dithering = true
    else
        self.hw_dithering = false
    end

    if self.hw_dithering then
        self.sw_dithering = false
    else
        -- We only handle SW dithering @ 8bpp, to keep things simple
        if self.device.screen.fb_bpp == 8 then
            self.sw_dithering = true
        else
            self.sw_dithering = false
        end
    end
end

-- To be overriden.
function fb:setSwipeAnimations(enabled)
end

-- To be overriden.
function fb:setSwipeDirection(direction)
end

function fb:getWaveformLevel()
    return math.min(self.wf_level_max, self.wf_level)
end

function fb:getMxcWaitForBypass()
    return self.mxcfb_bypass_wait_for
end

function fb:saveCurrentBB()
    if self.saved_bb then self.saved_bb:free() end
    self.saved_bb = self.bb:copy()
end

function fb:restoreFromSavedBB()
    if self.saved_bb then
        self.bb:blitFullFrom(self.saved_bb)
        -- free data
        self.saved_bb:free()
        self.saved_bb = nil
    end
end

function fb:shot(filename)
    -- Handle the RGB->BGR switcheroo if need be
    local bgr = false
    if self.device:hasBGRFrameBuffer() then
        bgr = true
    end
    self.bb:writePNG(filename, bgr)
end

-- Clear the screen to white
function fb:clear()
    if self.viewport then
        self.full_bb:fill(Blitbuffer.COLOR_WHITE)
    else
        self.bb:fill(Blitbuffer.COLOR_WHITE)
    end
end

return fb
