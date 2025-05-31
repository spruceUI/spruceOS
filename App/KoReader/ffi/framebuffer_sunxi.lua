local bit = require("bit")
local ffi = require("ffi")
local ffiUtil = require("ffi/util")
local C = ffi.C

require("ffi/posix_h")

local band = bit.band
local bor = bit.bor
local bnot = bit.bnot

local framebuffer = {
    -- pass device object here for proper model detection:
    device = nil,

    mech_poweron = nil,
    mech_wait_update_complete = nil,
    mech_wait_update_submission = nil,
    waveform_partial = nil,
    waveform_ui = nil,
    waveform_flashui = nil,
    waveform_full = nil,
    waveform_fast = nil,
    waveform_reagl = nil,
    waveform_night = nil,
    waveform_flashnight = nil,
    mech_refresh = nil,
    -- used to avoid waiting twice on the same marker
    dont_wait_for_marker = nil,

    -- We recycle ffi cdata
    marker_data = nil,
    g2d_rota = nil,
    area = nil,
    update = nil,
    ioc_cmd = nil,
}


--[[ refresh list management: --]]

-- Returns true if waveform_mode arg matches the UI waveform mode for the current device
-- NOTE: This is to avoid explicit comparison against device-specific waveform constants in disp_update()
function framebuffer:_isUIWaveFormMode(waveform_mode)
    return waveform_mode == self.waveform_ui
end

-- Returns true if waveform_mode arg matches the FlashUI waveform mode for the current device
-- NOTE: This is to avoid explicit comparison against device-specific waveform constants in disp_update()
function framebuffer:_isFlashUIWaveFormMode(waveform_mode)
    return waveform_mode == self.waveform_flashui
end

-- Returns true if waveform_mode arg matches the REAGL waveform mode for the current device
-- NOTE: This is to avoid explicit comparison against device-specific waveform constants in disp_update()
function framebuffer:_isREAGLWaveFormMode(waveform_mode)
    return waveform_mode == self.waveform_reagl
end

-- Returns true if waveform_mode arg matches the partial waveform mode for the current device
-- NOTE: This is to avoid explicit comparison against device-specific waveform constants in disp_update()
function framebuffer:_isPartialWaveFormMode(waveform_mode)
    return waveform_mode == self.waveform_partial
end

-- Returns the device-specific nightmode waveform mode
function framebuffer:_getNightWaveFormMode()
    return self.waveform_night
end

-- Returns the device-specific flashing nightmode waveform mode
function framebuffer:_getFlashNightWaveFormMode()
    return self.waveform_flashnight
end

-- Returns true if w & h are equal or larger than our visible screen estate (i.e., we asked for a full-screen update)
function framebuffer:_isFullScreen(w, h)
    -- NOTE: fb:getWidth() & fb:getHeight() return the viewport size, but obey rotation, which means we can't rely on them directly.
    --       fb:getScreenWidth() & fb:getScreenHeight return the full screen size, without the viewport, and in the default rotation, which doesn't help either.
    -- Settle for getWidth() & getHeight() w/ rotation handling, like what bb:getPhysicalRect() does...
    if band(self:getRotationMode(), 1) == 1 then w, h = h, w end

    if w >= self:getWidth() and h >= self:getHeight() then
        return true
    else
        return false
    end
end

--[[ handlers for the power management API of the eink driver --]]

local function kobo_sunxi_wakeup_epdc()
    ffiUtil.writeToSysfs("lcd0",   "/sys/kernel/debug/dispdbg/name")
    ffiUtil.writeToSysfs("enable", "/sys/kernel/debug/dispdbg/command")
    ffiUtil.writeToSysfs("1",      "/sys/kernel/debug/dispdbg/start")
end

--[[ handlers for the wait API of the eink driver --]]

-- Kobo's Mk8 DISP_EINK_WAIT_FRAME_SYNC_COMPLETE
local function kobo_sunxi_wait_for_update_complete(fb, marker)
    -- Wait for a specific update to be completed
    fb.ioc_cmd.wait_for.frame_id = marker
    return C.ioctl(fb.fd, C.DISP_EINK_WAIT_FRAME_SYNC_COMPLETE, fb.ioc_cmd)
end

-- Stub version that simply sleeps for 1ms
local function stub_wait_for_update_complete()
    return C.usleep(1000)
end


--[[ refresh functions ]]--

-- NOTE: Heavily based on framebuffer_mxcfb's mxc_update ;)
local function disp_update(fb, ioc_cmd, ioc_data, no_merge, is_flashing, waveform_mode, waveform_info, x, y, w, h)
    local bb = fb.full_bb or fb.bb

    -- If we're fresh off a rotation, make it full-screen and no_merge to avoid layer blending glitches...
    if fb._just_rotated then
        x = 0
        y = 0
        w = bb:getWidth()
        h = bb:getHeight()
        fb._just_rotated = nil
        no_merge = true
    end

    -- Sanitize refresh rect
    x, y, w, h = bb:getBoundedRect(x, y, w, h)
    x, y, w, h = bb:getPhysicalRect(x, y, w, h)

    -- Discard empty or bogus regions
    if w <= 1 or h <= 1 then
        fb.debug("discarding bogus refresh region, w:", w, "h:", h)
        return
    end

    -- Wake the EPDC up manually, in the vague hope it'll help with missed refreshes after a wakeup from standby...
    if fb.mech_poweron then
        fb:mech_poweron()
    end

    -- We've got the final region, update the area_info struct
    ioc_data.area.x_top = x
    ioc_data.area.y_top = y
    ioc_data.area.x_bottom = x + w - 1
    ioc_data.area.y_bottom = y + h - 1

    -- NOTE: If we're trying to send a:
    --         * REAGL update,
    --         * GC16 update,
    --         * Full-screen, flashing UI update,
    --       then wait for completion of previous marker first.
    local marker = fb.marker_data[0]
    -- Make sure the marker is valid, too.
    if (fb:_isREAGLWaveFormMode(waveform_mode)
      or waveform_mode == C.EINK_GC16_MODE
      or (is_flashing and fb:_isFlashUIWaveFormMode(waveform_mode) and fb:_isFullScreen(w, h)))
      and fb.mech_wait_update_complete
      and (marker ~= 0 and marker ~= fb.dont_wait_for_marker) then
        fb.debug("refresh: wait for completion of (previous) marker", marker)
        if fb:mech_wait_update_complete(marker) == -1 then
            local err = ffi.errno()
            fb.debug("DISP_EINK_WAIT_FRAME_SYNC_COMPLETE ioctl failed:", ffi.string(C.strerror(err)))
        end
    end

    -- Handle night mode shenanigans
    if fb.night_mode then
        -- Enforce a nightmode-specific mode to limit ghosting, where appropriate (i.e., partial & flashes).
        if fb:_isPartialWaveFormMode(waveform_mode) then
            waveform_mode = fb:_getNightWaveFormMode()
            waveform_info = band(waveform_info, bnot(C.EINK_REGAL_MODE))
        elseif waveform_mode == C.EINK_GC16_MODE or is_flashing then
            waveform_mode = fb:_getFlashNightWaveFormMode()
            waveform_info = band(waveform_info, bnot(C.EINK_REGAL_MODE))
        end
    end

    -- Handle the !flashing flag
    if not is_flashing and waveform_mode ~= C.EINK_AUTO_MODE then
        -- For some reason, AUTO shouldn't specify PARTIAL...
        -- (it trips the unknown mode warning, which falls back to... plain AUTO ;)).
        waveform_info = bor(waveform_info, C.EINK_PARTIAL_MODE)
    end

    -- Make sure we actually flash by bypassing the "working buffer was untouched" memcmp "optimization"...
    -- NOTE: This appeared in the Sage kernel on FW 4.29.
    -- NOTE: no_merge is always true if is_flashing is enabled, but we also have [ui] and [partial] modes
    --       that will request NO_MERGE without flashing, to avoid some more kernel bugs around collision handling...
    if no_merge then
        waveform_info = bor(waveform_info, C.EINK_NO_MERGE)
    end

    -- And finally bake mode + info into the update_mode bitmask
    ioc_data.update_mode = bor(waveform_mode, waveform_info)

    -- Recap the actual details of the ioctl, vs. what UIManager asked for...
    fb.debug(string.format("disp_update: %ux%u region @ (%u, %u) (WFM: %u [flash: %s])", w, h, x, y, waveform_mode, is_flashing))

    if C.ioctl(fb.fd, ioc_cmd, ioc_data) == -1 then
        local err = ffi.errno()
        fb.debug("DISP_EINK_UPDATE2 ioctl failed:", ffi.string(C.strerror(err)))
    end

    -- NOTE: We want to fence off FULL updates.
    --       c.f., framebuffer_mxcfb for more details.
    --       On sunxi, the actual update calls will block for sensibly longer than on mxcfb,
    --       so these are likely to always return immediately.
    if is_flashing and fb.mech_wait_update_complete then
        marker = fb.marker_data[0]
        fb.debug("refresh: wait for completion of marker", marker)
        if fb:mech_wait_update_complete(marker) == -1 then
            local err = ffi.errno()
            fb.debug("DISP_EINK_WAIT_FRAME_SYNC_COMPLETE ioctl failed:", ffi.string(C.strerror(err)))
        end
        -- And make sure we won't wait for it again, in case the next refresh trips one of our wait_for_*  heuristics ;).
        fb.dont_wait_for_marker = marker
    end
end

local function refresh_kobo_sunxi(fb, no_merge, is_flashing, waveform_mode, x, y, w, h)
    -- Store the auxiliary update flags in a separate bitmask we'll bake in later,
    -- as it makes identifying waveform modes easier in disp_update...
    local update_info = 0
    if waveform_mode == C.EINK_GLR16_MODE or waveform_mode == C.EINK_GLD16_MODE then
        update_info = bor(update_info, C.EINK_REGAL_MODE)
    end
    --[[
    -- NOTE: Unlike on mxcfb, this isn't HW assisted, this just uses the "simple" Y8->Y1 dither algorithm...
    --       As such, given the use-case for A2 (or DU, for that matter), this is wholly counter-productive ;).
    if waveform_mode == C.EINK_DU_MODE then
        update_info = bor(update_info, C.EINK_MONOCHROME)
    end
    --]]

    return disp_update(fb, C.DISP_EINK_UPDATE2, fb.update, no_merge, is_flashing, waveform_mode, update_info, x, y, w, h)
end


--[[ framebuffer API ]]--

function framebuffer:refreshPartialImp(x, y, w, h, dither)
    self.debug("refresh: partial", x, y, w, h, dither)
    self:mech_refresh(false, false, self.waveform_partial, x, y, w, h, dither)
end

function framebuffer:refreshNoMergePartialImp(x, y, w, h, dither)
    self.debug("refresh: no-merge partial w/ flash", x, y, w, h, dither)
    self:mech_refresh(true, false, self.waveform_partial, x, y, w, h, dither)
end

function framebuffer:refreshFlashPartialImp(x, y, w, h, dither)
    self.debug("refresh: partial w/ flash", x, y, w, h, dither)
    self:mech_refresh(true, true, self.waveform_partial, x, y, w, h, dither)
end

function framebuffer:refreshUIImp(x, y, w, h, dither)
    self.debug("refresh: ui-mode", x, y, w, h, dither)
    self:mech_refresh(false, false, self.waveform_ui, x, y, w, h, dither)
end

function framebuffer:refreshNoMergeUIImp(x, y, w, h, dither)
    self.debug("refresh: no-merge ui-mode w/ flash", x, y, w, h, dither)
    self:mech_refresh(true, false, self.waveform_ui, x, y, w, h, dither)
end

function framebuffer:refreshFlashUIImp(x, y, w, h, dither)
    self.debug("refresh: ui-mode w/ flash", x, y, w, h, dither)
    self:mech_refresh(true, true, self.waveform_flashui, x, y, w, h, dither)
end

function framebuffer:refreshFullImp(x, y, w, h, dither)
    self.debug("refresh: full", x, y, w, h, dither)
    self:mech_refresh(true, true, self.waveform_full, x, y, w, h, dither)
end

function framebuffer:refreshFastImp(x, y, w, h, dither)
    self.debug("refresh: fast", x, y, w, h, dither)
    self:mech_refresh(false, false, self.waveform_fast, x, y, w, h, dither)
end

function framebuffer:refreshA2Imp(x, y, w, h, dither)
    self.debug("refresh: A2", x, y, w, h, dither)
    self:mech_refresh(false, false, self.waveform_a2, x, y, w, h, dither)
end

function framebuffer:refreshWaitForLastImp()
    if self.mech_wait_update_complete and self.dont_wait_for_marker ~= self.marker_data[0] then
        self.debug("refresh: waiting for previous update", self.marker_data[0])
        self:mech_wait_update_complete(self.marker_data[0])
        self.dont_wait_for_marker = self.marker_data[0]
    end
end


function framebuffer:init()
    framebuffer.parent.init(self)

    if self.device:isKobo() then
        require("ffi/sunxi_kobo_h")

        self.mech_refresh = refresh_kobo_sunxi
        self.mech_wait_update_complete = kobo_sunxi_wait_for_update_complete

        -- NOTE: Nickel uses a mix of A2 & DU for the keyboard (A2 on keys, DU on the input field).
        --       We use A2 & GL16 to avoid losing AA on the input field.
        self.waveform_a2 = C.EINK_A2_MODE
        self.waveform_fast = C.EINK_DU_MODE
        self.waveform_ui = C.EINK_GL16_MODE
        -- You can't make GL16 flash :/
        self.waveform_flashui = C.EINK_GC16_MODE
        self.waveform_full = C.EINK_GC16_MODE
        self.waveform_partial = C.EINK_GLR16_MODE
        self.waveform_night = C.EINK_GLK16_MODE
        self.waveform_flashnight = C.EINK_GCK16_MODE

        self.mech_poweron = kobo_sunxi_wakeup_epdc

        local bypass_wait_for = self:getMxcWaitForBypass()
        -- If the user (or a device cap check) requested bypassing the WAIT_FOR ioctls, do so.
        if bypass_wait_for then
            -- The stub implementation just fakes this ioctl by sleeping for a tiny amount of time instead... :/.
            self.mech_wait_update_complete = stub_wait_for_update_complete
        end

        -- Keep our data structures around
        self.marker_data = ffi.new("uint32_t[1]")
        self.area = ffi.new("struct area_info")
        self.update = ffi.new("sunxi_disp_eink_update2")
        self.ioc_cmd = ffi.new("sunxi_disp_eink_ioctl")

        -- Start by setting up stuff that will never change
        self.update.area = self.area
        self.update.layer_num = 1
        self.update.lyr_cfg2 = self.layer  -- From framebuffer_ion
        self.update.frame_id = self.marker_data
        self.update.rotate = self.g2d_rota  -- From framebuffer_ion
        self.update.cfa_use = 0
    else
        error("unknown device type")
    end
end

return require("ffi/framebuffer_ion"):extend(framebuffer)
