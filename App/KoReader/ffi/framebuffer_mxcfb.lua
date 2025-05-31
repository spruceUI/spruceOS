local bit = require("bit")
local ffi = require("ffi")
local lfs = require("libs/libkoreader-lfs")
local ffiUtil = require("ffi/util")
local C = ffi.C

require("ffi/posix_h")

local band = bit.band
local bor = bit.bor
local bxor = bit.bxor

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
    night_is_reagl = nil,
    mech_refresh = nil,
    -- start with an invalid marker value to avoid doing something stupid on our first update
    marker = 0,
    -- used to avoid waiting twice on the same marker
    dont_wait_for_marker = nil,
    -- Set by frontend to 3 on Pocketbook Color Lux that refreshes based on bytes (not based on pixel)
    refresh_pixel_size = 1,

    -- We recycle ffi cdata
    marker_data = nil,
    update_data = nil,
    submission_data = nil,
}

--[[ refresh list management: --]]

-- Returns an incrementing marker value, w/ a sane wraparound for an uint32_t.
function framebuffer:_get_next_marker()
    local marker = self.marker + 1
    if marker > 0xFFFFFFFF then
        marker = 1
    end

    self.marker = marker
    return marker
end

-- Returns true if waveform_mode arg matches the UI waveform mode for the current device
-- NOTE: This is to avoid explicit comparison against device-specific waveform constants in mxc_update()
--       Here, it's because of the Kindle-specific WAVEFORM_MODE_GC16_FAST
function framebuffer:_isUIWaveFormMode(waveform_mode)
    return waveform_mode == self.waveform_ui
end

-- Returns true if waveform_mode arg matches the FlashUI waveform mode for the current device
-- NOTE: This is to avoid explicit comparison against device-specific waveform constants in mxc_update()
--       Here, it's because of the Kindle-specific WAVEFORM_MODE_GC16_FAST
function framebuffer:_isFlashUIWaveFormMode(waveform_mode)
    return waveform_mode == self.waveform_flashui
end

-- Returns true if waveform_mode arg matches the REAGL waveform mode for the current device
-- NOTE: This is to avoid explicit comparison against device-specific waveform constants in mxc_update()
--       Here, it's Kindle's various WAVEFORM_MODE_REAGL vs. Kobo's WAVEFORM_MODE_REAGLD
function framebuffer:_isREAGLWaveFormMode(waveform_mode)
    return waveform_mode == self.waveform_reagl
end

-- Returns true if the night waveform mode for the current device requires a REAGL promotion to FULL
function framebuffer:_isNightREAGL()
   return self.night_is_reagl
end

-- Returns true if waveform_mode arg matches the partial waveform mode for the current device
-- NOTE: This is to avoid explicit comparison against device-specific waveform constants in mxc_update()
--       Here, because of REAGL or device-specific quirks.
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

local function kobo_nxp_wakeup_epdc()
    -- First integer is the toggle, second is the poweroff delay in ms (only relevant when toggling power *off*, we just need it to make sscanf happy).
    ffiUtil.writeToSysfs("1,0", "/sys/class/graphics/fb0/power_state")
end

local function kobo_mtk_wakeup_epdc()
    ffiUtil.writeToSysfs("fiti_power 1", "/proc/hwtcon/cmd")
end

--[[ handlers for the wait API of the eink driver --]]

-- Kindle's MXCFB_WAIT_FOR_UPDATE_COMPLETE_PEARL == 0x4004462f
local function kindle_pearl_mxc_wait_for_update_complete(fb, marker)
    -- Wait for a specific update to be completed
    fb.marker_data[0] = marker

    return C.ioctl(fb.fd, C.MXCFB_WAIT_FOR_UPDATE_COMPLETE_PEARL, fb.marker_data)
end

-- Kobo's MXCFB_WAIT_FOR_UPDATE_COMPLETE_V1 == 0x4004462f
local function kobo_mxc_wait_for_update_complete(fb, marker)
    -- Wait for a specific update to be completed
    fb.marker_data[0] = marker

    return C.ioctl(fb.fd, C.MXCFB_WAIT_FOR_UPDATE_COMPLETE_V1, fb.marker_data)
end

-- Kobo's Mk7 MXCFB_WAIT_FOR_UPDATE_COMPLETE_V3
local function kobo_mk7_mxc_wait_for_update_complete(fb, marker)
    -- Wait for a specific update to be completed
    fb.marker_data.update_marker = marker

    return C.ioctl(fb.fd, C.MXCFB_WAIT_FOR_UPDATE_COMPLETE_V3, fb.marker_data)
end

-- Specialized variant for funky devices with an unreliable ioctl, where we're hoping doing this in pairs like Nickel *might* help...
-- NOTE: This is yet another attempt at dealing with those spurious timeouts...
--       FWIW, I can still randomly encounter those, even when doing this.
--       Which makes sense, as I have actually reproduced these in Nickel myself...
local function kobo_mk7_unreliable_mxc_wait_for_update_complete(fb, marker)
    -- If we can, wait for the *previous* marker first...
    if marker > 1 then
        -- Marker sanity check (the driver handles that, too, but it'll throw an EINVAL)
        fb.debug("refresh: wait for completion of buddy marker", marker - 1)
        fb.marker_data.update_marker = marker - 1
        if C.ioctl(fb.fd, C.MXCFB_WAIT_FOR_UPDATE_COMPLETE_V3, fb.marker_data) == -1 then
            local err = ffi.errno()
            fb.debug("MXCFB_WAIT_FOR_UPDATE_COMPLETE ioctl failed:", ffi.string(C.strerror(err)))
        end
    end

    -- Wait for a specific update to be completed
    fb.marker_data.update_marker = marker

    return C.ioctl(fb.fd, C.MXCFB_WAIT_FOR_UPDATE_COMPLETE_V3, fb.marker_data)
end

-- Kobo's HWTCON_WAIT_FOR_UPDATE_COMPLETE
local function kobo_mtk_wait_for_update_complete(fb, marker)
    -- Wait for a specific update to be completed
    fb.marker_data[0] = marker

    return C.ioctl(fb.fd, C.HWTCON_WAIT_FOR_UPDATE_COMPLETE, fb.marker_data)
end

-- Pocketbook's MXCFB_WAIT_FOR_UPDATE_COMPLETE_PB... with a twist.
local function pocketbook_mxc_wait_for_update_complete(fb, marker)
    -- Wait for a specific update to be completed
    -- NOTE: While the ioctl *should* only expect to read an uint32_t, some kernels still write back as if it were a struct,
    --       like on newer MXCFB_WAIT_FOR_UPDATE_COMPLETE ioctls...
    --       So, account for that by always passing an address to a mxcfb_update_marker_data struct to make the write safe.
    --       Given the layout of said struct (marker first), this thankfully works out just fine...
    --       c.f., https://github.com/koreader/koreader/issues/6000 & https://github.com/koreader/koreader/pull/6669
    fb.marker_data.update_marker = marker

    return C.ioctl(fb.fd, C.MXCFB_WAIT_FOR_UPDATE_COMPLETE_PB, fb.marker_data)
end

-- Remarkable MXCFB_WAIT_FOR_UPDATE_COMPLETE
local function remarkable_mxc_wait_for_update_complete(fb, marker)
    -- Wait for a specific update to be completed
    fb.marker_data.update_marker = marker

    return C.ioctl(fb.fd, C.MXCFB_WAIT_FOR_UPDATE_COMPLETE, fb.marker_data)
end

-- Sony PRS MXCFB_WAIT_FOR_UPDATE_COMPLETE
local function sony_prstux_mxc_wait_for_update_complete(fb, marker)
    -- Wait for a specific update to be completed
    fb.marker_data[0] = marker

    return C.ioctl(fb.fd, C.MXCFB_WAIT_FOR_UPDATE_COMPLETE, fb.marker_data)
end

-- BQ Cervantes MXCFB_WAIT_FOR_UPDATE_COMPLETE == 0x4004462f
local function cervantes_mxc_wait_for_update_complete(fb, marker)
    -- Wait for a specific update to be completed
    fb.marker_data[0] = marker

    return C.ioctl(fb.fd, C.MXCFB_WAIT_FOR_UPDATE_COMPLETE, fb.marker_data)
end

-- Kindle's MXCFB_WAIT_FOR_UPDATE_COMPLETE == 0xc008462f
local function kindle_carta_mxc_wait_for_update_complete(fb, marker)
    -- Wait for a specific update to be completed
    fb.marker_data.update_marker = marker

    return C.ioctl(fb.fd, C.MXCFB_WAIT_FOR_UPDATE_COMPLETE, fb.marker_data)
end

-- Kindle's MXCFB_WAIT_FOR_UPDATE_SUBMISSION == 0x40044637
local function kindle_mxc_wait_for_update_submission(fb, marker)
    -- Wait for a specific update to be submitted
    fb.submission_data[0] = marker

    return C.ioctl(fb.fd, C.MXCFB_WAIT_FOR_UPDATE_SUBMISSION, fb.submission_data)
end

-- Kobo's HWTCON_WAIT_FOR_UPDATE_SUBMISSION
local function kobo_mtk_wait_for_update_submission(fb, marker)
    -- Wait for a specific update to be submitted
    fb.submission_data[0] = marker

    return C.ioctl(fb.fd, C.HWTCON_WAIT_FOR_UPDATE_SUBMISSION, fb.submission_data)
end

-- Stub version that simply sleeps for 2.5ms
-- This is roughly ten times the amount of time a real *NOP* WAIT_FOR_UPDATE_COMPLETE would take.
-- An effective one could block for ~150ms to north of 500ms, depending on the waveform mode of the waited on marker.
local function stub_mxc_wait_for_update_complete(fb, marker, us)
    return C.usleep(us or 2500)
end

--[[ refresh functions ]]--

-- Kindle's MXCFB_SEND_UPDATE == 0x4048462e
-- Kobo's MXCFB_SEND_UPDATE == 0x4044462e
-- Pocketbook's MXCFB_SEND_UPDATE == 0x4040462e
-- Cervantes MXCFB_SEND_UPDATE == 0x4044462e
local function mxc_update(fb, ioc_cmd, ioc_data, is_flashing, waveform_mode, x, y, w, h, dither)
    local bb = fb.full_bb or fb.bb

    -- NOTE: If we're requesting hardware dithering on a partial update, make sure the rectangle is using
    --       coordinates aligned to the previous multiple of 8, and dimensions aligned to the next multiple of 8.
    --       Otherwise, some unlucky coordinates will play badly with the PxP's own alignment constraints,
    --       leading to a refresh where content appears to have moved a few pixels to the side...
    --       (Sidebar: this is probably a kernel issue, the EPDC driver is responsible for the alignment fixup,
    --       c.f., epdc_process_update @ drivers/video/fbdev/mxc/mxc_epdc_v2_fb.c on a Kobo Mk. 7 kernel...).
    -- And regardless of alignment constraints, make sure the rectangle is strictly bounded inside the screen.
    x, y, w, h = bb:getBoundedRect(x, y, w, h, dither and 8)
    -- The ioctl operates in the native rotation, so, make sure we rotate the rectangle as needed
    x, y, w, h = bb:getPhysicalRect(x, y, w, h)

    -- NOTE: Discard empty or bogus regions, as they might murder some kernels with extreme prejudice...
    -- (c.f., https://github.com/NiLuJe/FBInk/blob/5449a03d3be28823991b425cd20aa048d2d71845/fbink.c#L1755).
    -- We have practical experience of that with 1x1 pixel blocks on Kindle PW2 and KV,
    -- c.f., koreader/koreader#1299 and koreader/koreader#1486
    if w <= 1 or h <= 1 then
        fb.debug("discarding bogus refresh region, w:", w, "h:", h)
        return
    end

    -- Wake the EPDC up manually (don't ask me why this would make any sort of sense, it's simply what Nickel does on devices where we *can* do it...)
    -- NOTE: Technically, it makes a little more sense when you put it in context of *how* Nickel does that: it's not actually tied to the refresh or the wait there,
    --       but to *touch* input: on any registered *touch* input (physical buttons are exempt, for some reason), Nickel will forcibly awaken the EPDC,
    --       unless that was already done less than roughly 1.5s ago.
    --       Think of something like some properly implemented & tuned kernels with the interactive cpufreq governor that will boost on touch input, for instance.
    --       In practice, that still trips *very* close to the ioctl (but may not always come *before* a [wait -> refresh -> wait] sandwich;
    --       e.g., I mostly see it before the refresh on NXP & sunxi, but I mostly see it in front of everything on MTK).
    --       TL;DR: Because, on devices flagged !hasReliableMxcWaitFor, we were seeing deadlock issues with refreshes that aren't necessarily tied to input,
    --       (and for simplicity's sake), we simply unconditionally do this here as early possible.
    -- NOTE: This might be a gigantic red herring, and simply a case of the very few extra cpu cycles involved throwing off the race...
    if fb.mech_poweron then
        fb:mech_poweron()
    end

    w = w * fb.refresh_pixel_size

    -- NOTE: If we're trying to send a:
    --         * true FULL update,
    --         * GC16_FAST update (i.e., popping-up a menu),
    --       then wait for submission of previous marker first.
    local marker = fb.marker
    -- NOTE: Technically, we might not always want to wait for *exactly* the previous marker
    --       (we might actually want the one before that), but in the vast majority of cases, that's good enough,
    --       and saves us a lot of annoying and hard-to-get-right heuristics anyway ;).
    -- Make sure it's a valid marker, to avoid doing something stupid on our first update.
    -- Also make sure we haven't already waited on this marker ;).
    if fb.mech_wait_update_submission
      and (is_flashing or fb:_isUIWaveFormMode(waveform_mode))
      and (marker ~= 0 and marker ~= fb.dont_wait_for_marker) then
        fb.debug("refresh: wait for submission of (previous) marker", marker)
        if fb:mech_wait_update_submission(marker) == -1 then
            local err = ffi.errno()
            fb.debug("MXCFB_WAIT_FOR_UPDATE_SUBMISSION ioctl failed:", ffi.string(C.strerror(err)))
        end
        -- NOTE: We don't set dont_wait_for_marker here,
        --       as we *do* want to chain wait_for_submission & wait_for_complete in some rare instances...
    end

    -- NOTE: If we're trying to send a:
    --         * REAGL update,
    --         * GC16 update (so far, the constant value for that one is universal),
    --         * Full-screen, flashing UI update,
    --       then wait for completion of previous marker first.
    -- Again, make sure the marker is valid, too.
    if (fb:_isREAGLWaveFormMode(waveform_mode)
      or waveform_mode == C.WAVEFORM_MODE_GC16
      or (is_flashing and fb:_isFlashUIWaveFormMode(waveform_mode) and fb:_isFullScreen(w, h)))
      and fb.mech_wait_update_complete
      and (marker ~= 0 and marker ~= fb.dont_wait_for_marker) then
        fb.debug("refresh: wait for completion of (previous) marker", marker)
        if fb:mech_wait_update_complete(marker) == -1 then
            local err = ffi.errno()
            fb.debug("MXCFB_WAIT_FOR_UPDATE_COMPLETE ioctl failed:", ffi.string(C.strerror(err)))
        end
    end

    ioc_data.update_mode = is_flashing and C.UPDATE_MODE_FULL or C.UPDATE_MODE_PARTIAL
    ioc_data.waveform_mode = waveform_mode or C.WAVEFORM_MODE_GC16
    ioc_data.update_region.left = x
    ioc_data.update_region.top = y
    ioc_data.update_region.width = w
    ioc_data.update_region.height = h
    marker = fb:_get_next_marker()
    ioc_data.update_marker = marker

    -- Handle night mode shenanigans
    if fb.night_mode then
        -- We're in nightmode!
        -- If the device can do HW inversion safely, and doesn't already handle setting the flag automatically, do that!
        if fb.device:canHWInvert() and not fb:getHWNightmode() then
            ioc_data.flags = bor(ioc_data.flags, C.EPDC_FLAG_ENABLE_INVERSION)
        end

        -- Enforce a nightmode-specific mode (usually, GC16), to limit ghosting, where appropriate (i.e., partial & flashes).
        -- There's nothing much we can do about crappy flashing behavior on some devices, though (c.f., base/#884),
        -- that's in the hands of the EPDC. Kindle PW2+ behave sanely, for instance, even when flashing on AUTO or GC16 ;).
        if fb:_isPartialWaveFormMode(waveform_mode) then
            waveform_mode = fb:_getNightWaveFormMode()
            ioc_data.waveform_mode = waveform_mode
            -- And handle devices like the KOA2/PW4, where night is a REAGL waveform that needs to be FULL...
            if fb:_isNightREAGL() then
                ioc_data.update_mode = C.UPDATE_MODE_FULL
            end
        elseif waveform_mode == C.WAVEFORM_MODE_GC16 or is_flashing then
            waveform_mode = fb:_getFlashNightWaveFormMode()
            ioc_data.waveform_mode = waveform_mode
        end
    end

    -- Handle REAGL promotion...
    -- NOTE: We need to do this here, because we rely on the pre-promotion actual is_flashing in previous heuristics.
    if fb:_isREAGLWaveFormMode(waveform_mode) then
        -- NOTE: REAGL updates always need to be full.
        ioc_data.update_mode = C.UPDATE_MODE_FULL
    end

    -- Recap the actual details of the ioctl, vs. what UIManager asked for...
    fb.debug(string.format("mxc_update: %ux%u region @ (%u, %u) with marker %u (WFM: %u & UPD: %u)", w, h, x, y, marker, ioc_data.waveform_mode, ioc_data.update_mode))

    if C.ioctl(fb.fd, ioc_cmd, ioc_data) == -1 then
        local err = ffi.errno()
        fb.debug("MXCFB_SEND_UPDATE ioctl failed:", ffi.string(C.strerror(err)))
    end

    -- NOTE: We want to fence off FULL updates.
    --       Mainly to mimic stock readers, but also because there's a good reason to do it:
    --       forgoing that can yield slightly "jittery" looking screens when multiple flashes are shown on screen and not in sync.
    --       To achieve that, we could simply store this marker, and wait for it on the *next* refresh,
    --       ensuring the wait would potentially be shorter, or even null.
    --       In practice, we won't actually be busy for a bit after most (if not all) flashing refresh calls,
    --       so we can instead afford to wait for it right now, which *will* block for a while,
    --       but will save us an ioctl before the next refresh, something which, even if it didn't block at all,
    --       would possibly end up being more detrimental to latency/reactivity.
    if ioc_data.update_mode == C.UPDATE_MODE_FULL
      and fb.mech_wait_update_complete then
        fb.debug("refresh: wait for completion of marker", marker)
        if fb:mech_wait_update_complete(marker) == -1 then
            local err = ffi.errno()
            fb.debug("MXCFB_WAIT_FOR_UPDATE_COMPLETE ioctl failed:", ffi.string(C.strerror(err)))
        end
        -- And make sure we won't wait for it again, in case the next refresh trips one of our wait_for_*  heuristics ;).
        fb.dont_wait_for_marker = marker
    end
end

local function refresh_k51(fb, is_flashing, waveform_mode, x, y, w, h)
    -- only for Amazon's driver, try to mostly follow what the stock reader does...
    if waveform_mode == C.WAVEFORM_MODE_REAGL then
        -- If we're requesting WAVEFORM_MODE_REAGL, it's REAGL all around!
        fb.update_data.hist_bw_waveform_mode = waveform_mode
        fb.update_data.hist_gray_waveform_mode = waveform_mode
    else
        fb.update_data.hist_bw_waveform_mode = C.WAVEFORM_MODE_DU
        fb.update_data.hist_gray_waveform_mode = C.WAVEFORM_MODE_GC16_FAST
    end
    -- And we're only left with true full updates to special-case.
    if waveform_mode == C.WAVEFORM_MODE_GC16 then
        fb.update_data.hist_gray_waveform_mode = waveform_mode
    end

    -- NOTE: Enable the appropriate flag when requesting an any->2bit update.
    -- Since we mainly use DU for highlights, the color decimation quantization will effectively crush antialiasing on text,
    -- avoiding making the text look fuzzy during the refresh (it'll instead look blockier, because of the lack of AA).
    -- The higher density the screen is, the better this approach will look vs. fuzzy refresh artifacts ;).
    -- In the very few cases we use A2 (i.e., the keyboard), using FORCE_MONOCHROME would be actively harmful:
    -- we only highlight a border around the key, so we don't actually modify the glyph;
    -- since non-GC updates leave untouched pixels alone, we leave the glyph (and its AA!) alone.
    -- If we used FORCE_MONOCHROME, it would affect the whole rectangle, crushing the AA,
    -- and the A2 update would have to pick up the modified pixels, leading to worse results.
    if waveform_mode == C.WAVEFORM_MODE_DU then
        fb.update_data.flags = C.EPDC_FLAG_FORCE_MONOCHROME
    else
        fb.update_data.flags = 0
    end

    return mxc_update(fb, C.MXCFB_SEND_UPDATE, fb.update_data, is_flashing, waveform_mode, x, y, w, h)
end

local function refresh_zelda(fb, is_flashing, waveform_mode, x, y, w, h, dither)
    -- Only for Amazon's driver, try to mostly follow what the stock reader does...
    if waveform_mode == C.WAVEFORM_MODE_ZELDA_GLR16 or waveform_mode == C.WAVEFORM_MODE_ZELDA_GLD16 then
        -- If we're requesting WAVEFORM_MODE_ZELDA_GLR16, it's REAGL all around!
        fb.update_data.hist_bw_waveform_mode = waveform_mode
        fb.update_data.hist_gray_waveform_mode = waveform_mode
    else
        fb.update_data.hist_bw_waveform_mode = C.WAVEFORM_MODE_DU
        fb.update_data.hist_gray_waveform_mode = C.WAVEFORM_MODE_GC16 -- NOTE: GC16_FAST points to GC16
    end

    -- Did we request HW dithering on a device where it works?
    if dither and fb.device:canHWDither() then
        fb.update_data.dither_mode = C.EPDC_FLAG_USE_DITHERING_ORDERED
        if waveform_mode == C.WAVEFORM_MODE_ZELDA_A2 or waveform_mode == C.WAVEFORM_MODE_DU then
            fb.update_data.quant_bit = 1
        else
            fb.update_data.quant_bit = 7
        end
    else
        fb.update_data.dither_mode = C.EPDC_FLAG_USE_DITHERING_PASSTHROUGH
        fb.update_data.quant_bit = 0
    end
    -- Enable the REAGLD algo when requested
    if waveform_mode == C.WAVEFORM_MODE_ZELDA_GLD16 then
        fb.update_data.flags = C.EPDC_FLAG_USE_ZELDA_REGAL
    -- Enable the appropriate flag when requesting an any->2bit update, provided we're not dithering.
    elseif waveform_mode == C.WAVEFORM_MODE_DU and not dither then
        fb.update_data.flags = C.EPDC_FLAG_FORCE_MONOCHROME
    else
        fb.update_data.flags = 0
    end

    return mxc_update(fb, C.MXCFB_SEND_UPDATE_ZELDA, fb.update_data, is_flashing, waveform_mode, x, y, w, h, dither)
end

local function refresh_rex(fb, is_flashing, waveform_mode, x, y, w, h, dither)
    -- Only for Amazon's driver, try to mostly follow what the stock reader does...
    if waveform_mode == C.WAVEFORM_MODE_ZELDA_GLR16 or waveform_mode == C.WAVEFORM_MODE_ZELDA_GLD16 then
        -- If we're requesting WAVEFORM_MODE_ZELDA_GLR16, it's REAGL all around!
        fb.update_data.hist_bw_waveform_mode = waveform_mode
        fb.update_data.hist_gray_waveform_mode = waveform_mode
    else
        fb.update_data.hist_bw_waveform_mode = C.WAVEFORM_MODE_DU
        fb.update_data.hist_gray_waveform_mode = C.WAVEFORM_MODE_GC16 -- NOTE: GC16_FAST points to GC16
    end

    -- Did we request HW dithering on a device where it works?
    if dither and fb.device:canHWDither() then
        fb.update_data.dither_mode = C.EPDC_FLAG_USE_DITHERING_ORDERED
        if waveform_mode == C.WAVEFORM_MODE_ZELDA_A2 or waveform_mode == C.WAVEFORM_MODE_DU then
            fb.update_data.quant_bit = 1
        else
            fb.update_data.quant_bit = 7
        end
    else
        fb.update_data.dither_mode = C.EPDC_FLAG_USE_DITHERING_PASSTHROUGH
        fb.update_data.quant_bit = 0
    end
    -- Enable the REAGLD algo when requested
    if waveform_mode == C.WAVEFORM_MODE_ZELDA_GLD16 then
        fb.update_data.flags = C.EPDC_FLAG_USE_ZELDA_REGAL
    -- Enable the appropriate flag when requesting an any->2bit update, provided we're not dithering.
    elseif waveform_mode == C.WAVEFORM_MODE_DU and not dither then
        fb.update_data.flags = C.EPDC_FLAG_FORCE_MONOCHROME
    else
        fb.update_data.flags = 0
    end

    return mxc_update(fb, C.MXCFB_SEND_UPDATE_REX, fb.update_data, is_flashing, waveform_mode, x, y, w, h, dither)
end

local function refresh_mtk(fb, is_flashing, waveform_mode, x, y, w, h, dither)
    -- Actually unused by the driver...
    if waveform_mode == C.MTK_WAVEFORM_MODE_GLR16 or waveform_mode == C.MTK_WAVEFORM_MODE_GLD16 then
        -- If we're requesting MTK_WAVEFORM_MODE_GLR16, it's REAGL all around!
        fb.update_data.hist_bw_waveform_mode = waveform_mode
        fb.update_data.hist_gray_waveform_mode = waveform_mode
    else
        fb.update_data.hist_bw_waveform_mode = C.MTK_WAVEFORM_MODE_DU
        fb.update_data.hist_gray_waveform_mode = C.MTK_WAVEFORM_MODE_GC16 -- NOTE: GC16_FAST points to GC16
    end

    -- Enable the appropriate flag when requesting an any->2bit update, provided we're not dithering.
    -- NOTE: See FBInk note about DITHER + MONOCHROME
    if waveform_mode == C.MTK_WAVEFORM_MODE_DU and not dither then
        fb.update_data.flags = C.EPDC_FLAG_FORCE_MONOCHROME
    else
        fb.update_data.flags = 0
    end

    -- Did we request HW dithering?
    if dither and fb.device:canHWDither() then
        fb.update_data.flags = bor(fb.update_data.flags, C.MTK_EPDC_FLAG_USE_DITHERING_Y4)
    end

    if fb.swipe_animations then
        -- The MTK Driver will crash if given a area smaller than the number of steps.
        -- If direction is L/R and w is smaller or if it is U/D and h is smaller
        -- Being as one genneraly will only want animations on a larger area, and I am too
        -- lazy to test for direction, disable animations when w or h is less than steps.
        if w >= fb.update_data.swipe_data.steps and h >= fb.update_data.swipe_data.steps then
            fb.update_data.flags = bor(fb.update_data.flags, C.MTK_EPDC_FLAG_ENABLE_SWIPE)
        end
        fb.swipe_animations = false
    end

    return mxc_update(fb, C.MXCFB_SEND_UPDATE_MTK, fb.update_data, is_flashing, waveform_mode, x, y, w, h, dither)
end

-- Enable swipe animations. They will be reset at the next refresh.
function framebuffer:_MTK_SetSwipeAnimations(enabled)
    self.swipe_animations = enabled
end

-- Set the swipe animation direction. This is sticky
function framebuffer:_MTK_SetSwipeDirection(left)
    local swipe_direction = left and C.MTK_SWIPE_LEFT or C.MTK_SWIPE_RIGHT
    -- Account for KOReader rotation not matching the FB rotation with some bit trickery.
    -- Alternatively here is a LUT:
    -- local lut = { -- L R D U
    --                { 2,3,0,1},
    --                { 0,1,3,2},
    --                { 3,2,1,0},
    --                { 1,0,2,3}
    --             }
    -- swipe_direction = lut[self.cur_rotation_mode][swipe_direction]
    local rota = self.cur_rotation_mode
    if rota ~= self.DEVICE_ROTATED_UPRIGHT then
        if rota == self.DEVICE_ROTATED_UPSIDE_DOWN then
            swipe_direction = bxor(swipe_direction, 1)
        elseif bor(swipe_direction, 1) == bor(rota, 1) then
            swipe_direction = bxor(swipe_direction, 3)
        else
            swipe_direction = bxor(swipe_direction, 2)
        end
    end
    --self.debug("MTK Rota:", rota, "Swipe:", swipe_direction, "Comp:", swipe_direction)
    self.update_data.swipe_data.direction = swipe_direction
end

-- Don't let the driver silently upgrade to REAGL
function framebuffer:_MTK_ToggleFastMode(toggle)
    local flags = ffi.new("uint32_t[1]", bor(C.UPDATE_FLAGS_FAST_MODE, toggle and C.UPDATE_FLAGS_MODE_FAST_FLAG or 0))

    if C.ioctl(self.fd, C.MXCFB_SET_UPDATE_FLAGS_MTK, flags) == -1 then
        local err = ffi.errno()
        self.debug("MXCFB_SET_UPDATE_FLAGS_MTK ioctl failed:", ffi.string(C.strerror(err)))
    end
end

local function refresh_kobo(fb, is_flashing, waveform_mode, x, y, w, h)
    -- Enable the appropriate flag when requesting a REAGLD waveform (WAVEFORM_MODE_REAGLD on the Aura)
    if waveform_mode == C.WAVEFORM_MODE_REAGLD then
        fb.update_data.flags = C.EPDC_FLAG_USE_AAD
    elseif waveform_mode == C.WAVEFORM_MODE_DU then
        -- As well as when requesting an any->2bit waveform
        fb.update_data.flags = C.EPDC_FLAG_FORCE_MONOCHROME
    else
        fb.update_data.flags = 0
    end

    return mxc_update(fb, C.MXCFB_SEND_UPDATE_V1_NTX, fb.update_data, is_flashing, waveform_mode, x, y, w, h)
end

local function refresh_kobo_mk7(fb, is_flashing, waveform_mode, x, y, w, h, dither)
    -- Did we request HW dithering?
    if dither then
        fb.update_data.dither_mode = C.EPDC_FLAG_USE_DITHERING_ORDERED
        if waveform_mode == C.WAVEFORM_MODE_A2 or waveform_mode == C.WAVEFORM_MODE_DU then
            fb.update_data.quant_bit = 1
        else
            fb.update_data.quant_bit = 7
        end
    else
        fb.update_data.dither_mode = C.EPDC_FLAG_USE_DITHERING_PASSTHROUGH
        fb.update_data.quant_bit = 0
    end
    -- Enable the appropriate flag when requesting an any->2bit update, provided we're not dithering.
    -- NOTE: As of right now (FW 4.9.x), WAVEFORM_MODE_GLD16 appears not to be used by Nickel,
    --       so we don't have to care about EPDC_FLAG_USE_REGAL
    -- NOTE: We barely ever actually request A2 updates anymore (on any platform, actually), but,
    --       on Mk. 7 specifically, we want to avoid stacking EPDC_FLAGs,
    --       because the kernel is buggy (c.f., https://github.com/NiLuJe/FBInk/blob/96a2cd6a93f5184c595c0e53a844fd883adfd75b/fbink.c#L2422-L2440).
    if waveform_mode == C.WAVEFORM_MODE_DU and not dither then
        fb.update_data.flags = C.EPDC_FLAG_FORCE_MONOCHROME
    else
        fb.update_data.flags = 0
    end

    return mxc_update(fb, C.MXCFB_SEND_UPDATE_V2, fb.update_data, is_flashing, waveform_mode, x, y, w, h, dither)
end

local function refresh_kobo_mtk(fb, is_flashing, waveform_mode, x, y, w, h, dither)
    -- FIXME: Enable this, assuming it actually fits our purpose.
    -- Enable the appropriate flag when requesting an any->2bit update, provided we're not dithering.
    -- NOTE: See FBInk note about DITHER + MONOCHROME
    --[[
    if waveform_mode == C.HWTCON_WAVEFORM_MODE_DU and not dither then
        fb.update_data.flags = C.HWTCON_FLAG_FORCE_A2_OUTPUT
    else
        fb.update_data.flags = 0
    end
    --]]
    fb.update_data.flags = 0

    -- Did we request HW dithering?
    if dither and fb.device:canHWDither() then
        fb.update_data.flags = bor(fb.update_data.flags, C.HWTCON_FLAG_USE_DITHERING)

        if waveform_mode == C.HWTCON_WAVEFORM_MODE_DU or waveform_mode == C.HWTCON_WAVEFORM_MODE_A2 then
            fb.update_data.dither_mode = C.HWTCON_FLAG_USE_DITHERING_Y8_Y1_S
        else
            fb.update_data.dither_mode = C.HWTCON_FLAG_USE_DITHERING_Y8_Y4_S
        end
    end

    return mxc_update(fb, C.HWTCON_SEND_UPDATE, fb.update_data, is_flashing, waveform_mode, x, y, w, h, dither)
end

local function refresh_pocketbook(fb, is_flashing, waveform_mode, x, y, w, h)
    -- TEMP_USE_AMBIENT, not that there was ever any other choice...
    fb.update_data.temp = C.TEMP_USE_AMBIENT
    -- Enable the appropriate flag when requesting a REAGLD waveform (EPDC_WFTYPE_AAD on PB631)
    if waveform_mode == C.EPDC_WFTYPE_AAD then
        fb.update_data.flags = C.EPDC_FLAG_USE_AAD
    elseif waveform_mode == C.WAVEFORM_MODE_DU then
        -- As well as when requesting an any->2bit waveform
        --- @note: Much like on rM, it appears faking 24°C instead of relying on ambient temp leads to lower latency
        fb.update_data.temp = 24
        fb.update_data.flags = C.EPDC_FLAG_FORCE_MONOCHROME
    else
        fb.update_data.flags = 0
    end

    return mxc_update(fb, C.MXCFB_SEND_UPDATE, fb.update_data, is_flashing, waveform_mode, x, y, w, h)
end

local function refresh_remarkable(fb, is_flashing, waveform_mode, x, y, w, h)
    if waveform_mode == C.WAVEFORM_MODE_DU then
       fb.update_data.temp = C.TEMP_USE_REMARKABLE
    else
       fb.update_data.temp = C.TEMP_USE_AMBIENT
    end
    return mxc_update(fb, C.MXCFB_SEND_UPDATE, fb.update_data, is_flashing, waveform_mode, x, y, w, h)
end

local function refresh_sony_prstux(fb, is_flashing, waveform_mode, x, y, w, h)
    return mxc_update(fb, C.MXCFB_SEND_UPDATE, fb.update_data, is_flashing, waveform_mode, x, y, w, h)
end

local function refresh_cervantes(fb, is_flashing, waveform_mode, x, y, w, h)
    if waveform_mode == C.WAVEFORM_MODE_DU then
        fb.update_data.flags = C.EPDC_FLAG_FORCE_MONOCHROME
    else
        fb.update_data.flags = 0
    end
    return mxc_update(fb, C.MXCFB_SEND_UPDATE, fb.update_data, is_flashing, waveform_mode, x, y, w, h)
end


--[[ framebuffer API ]]--

function framebuffer:refreshPartialImp(x, y, w, h, dither)
    self.debug("refresh: partial", x, y, w, h, dither)
    self:mech_refresh(false, self.waveform_partial, x, y, w, h, dither)
end

function framebuffer:refreshFlashPartialImp(x, y, w, h, dither)
    self.debug("refresh: partial w/ flash", x, y, w, h, dither)
    self:mech_refresh(true, self.waveform_partial, x, y, w, h, dither)
end

function framebuffer:refreshUIImp(x, y, w, h, dither)
    self.debug("refresh: ui-mode", x, y, w, h, dither)
    self:mech_refresh(false, self.waveform_ui, x, y, w, h, dither)
end

function framebuffer:refreshFlashUIImp(x, y, w, h, dither)
    self.debug("refresh: ui-mode w/ flash", x, y, w, h, dither)
    self:mech_refresh(true, self.waveform_flashui, x, y, w, h, dither)
end

function framebuffer:refreshFullImp(x, y, w, h, dither)
    self.debug("refresh: full", x, y, w, h, dither)
    self:mech_refresh(true, self.waveform_full, x, y, w, h, dither)
end

function framebuffer:refreshFastImp(x, y, w, h, dither)
    self.debug("refresh: fast", x, y, w, h, dither)
    self:mech_refresh(false, self.waveform_fast, x, y, w, h, dither)
end

function framebuffer:refreshA2Imp(x, y, w, h, dither)
    self.debug("refresh: A2", x, y, w, h, dither)
    self:mech_refresh(false, self.waveform_a2, x, y, w, h, dither)
end

function framebuffer:refreshWaitForLastImp()
    if self.mech_wait_update_complete and self.dont_wait_for_marker ~= self.marker then
        self.debug("refresh: waiting for previous update", self.marker)
        self:mech_wait_update_complete(self.marker)
        self.dont_wait_for_marker = self.marker
    end
end

-- Detect Allwinner boards. Those emulate mxcfb API in a custom driver (poorly).
function framebuffer:isB288(fb)
    require("ffi/mxcfb_pocketbook_h")
    -- On a real MXC driver, it returns -EINVAL
    return C.ioctl(self.fd, C.EPDC_GET_UPDATE_STATE, ffi.new("uint32_t[1]")) == 0
end

function framebuffer:init()
    framebuffer.parent.init(self)

    if self.device:isKindle() then
        require("ffi/mxcfb_kindle_h")

        self.mech_refresh = refresh_k51
        self.mech_wait_update_complete = kindle_pearl_mxc_wait_for_update_complete
        self.mech_wait_update_submission = kindle_mxc_wait_for_update_submission

        self.waveform_a2 = C.WAVEFORM_MODE_A2
        self.waveform_fast = C.WAVEFORM_MODE_DU
        self.waveform_ui = C.WAVEFORM_MODE_GC16_FAST
        self.waveform_flashui = self.waveform_ui
        self.waveform_full = C.WAVEFORM_MODE_GC16
        self.waveform_night = C.WAVEFORM_MODE_GC16
        self.waveform_flashnight = self.waveform_night
        self.night_is_reagl = false

        if self.device:isREAGL() then
            self.mech_wait_update_complete = kindle_carta_mxc_wait_for_update_complete
            self.waveform_fast = C.WAVEFORM_MODE_DU -- NOTE: DU, because A2 looks terrible on REAGL devices. Older devices/FW may be using AUTO in this instance.
            self.waveform_reagl = C.WAVEFORM_MODE_REAGL
            self.waveform_partial = self.waveform_reagl
            -- NOTE: GL16_INV is available since FW >= 5.6.x only, but it'll safely fall-back to AUTO on older FWs.
            --       Most people with those devices should be running at least FW 5.9.7 by now, though ;).
            self.waveform_night = C.WAVEFORM_MODE_GL16_INV
            self.waveform_flashnight = C.WAVEFORM_MODE_GC16
        else
            self.waveform_fast = C.WAVEFORM_MODE_DU -- NOTE: DU, because A2 looks terrible on the Touch, and ghosts horribly. Framework is actually using AUTO for UI feedback inverts.
            self.waveform_partial = C.WAVEFORM_MODE_GL16_FAST -- NOTE: Depending on FW, might instead be AUTO w/ hist_gray_waveform_mode set to GL16_FAST
        end

        -- NOTE: Devices on the Rex platform essentially use the same driver as the Zelda platform, they're just passing a slightly smaller mxcfb_update_data struct
        if self.device:isZelda() or self.device:isRex() then
            if self.device:isZelda() then
                self.mech_refresh = refresh_zelda
            else
                self.mech_refresh = refresh_rex
            end

            self.waveform_a2 = C.WAVEFORM_MODE_ZELDA_A2
            self.waveform_fast = C.WAVEFORM_MODE_DU
            self.waveform_ui = C.WAVEFORM_MODE_AUTO
            -- NOTE: Possibly to bypass the possibility that AUTO, even when FULL, might not flash (something which holds true for a number of devices, especially on small regions),
            --       Zelda explicitly requests GC16 when flashing an UI element that doesn't cover the full screen...
            --       And it resorts to AUTO when PARTIAL, because GC16_FAST is no more (it points to GC16).
            self.waveform_flashui = C.WAVEFORM_MODE_GC16
            self.waveform_reagl = C.WAVEFORM_MODE_ZELDA_GLR16
            self.waveform_partial = self.waveform_reagl
            -- NOTE: Because we can't have nice things, we have to account for devices that do not actuallly support the fancy inverted waveforms...
            if self.device:isNightModeChallenged() then
                self.waveform_night = C.WAVEFORM_MODE_ZELDA_GL16_INV -- NOTE: Currently points to the bog-standard GL16, but one can hope...
                self.waveform_flashnight = C.WAVEFORM_MODE_GC16
            else
                self.waveform_night = C.WAVEFORM_MODE_ZELDA_GLKW16
                self.night_is_reagl = true
                self.waveform_flashnight = C.WAVEFORM_MODE_ZELDA_GCK16
            end
        end

        -- NOTE: Despite the vastly different SoC, lab126 did the sane thing, and designed the new driver after the mxcfb API ;).
        if self.device:isMTK() then
            self.mech_refresh = refresh_mtk

            self.waveform_a2 = C.MTK_WAVEFORM_MODE_A2
            self.waveform_fast = C.MTK_WAVEFORM_MODE_DU
            self.waveform_ui = C.WAVEFORM_MODE_AUTO
            self.waveform_flashui = self.waveform_ui
            self.waveform_reagl = C.MTK_WAVEFORM_MODE_GLR16
            self.waveform_partial = self.waveform_reagl
            -- NOTE: We switch to nightmode globally, via the grayscale vinfo fb flag,
            --       as the driver uses that to make a few nightmode-specific decisions:
            --         * Proper pattern color for the halftone grid
            --         * Automatic GCK16/GLKW16/DUNM waveform mode selection
            --         * Disable the silent REAGL updates in nightmode
            --         * Use the proper waveform mode during animated swipes
            --         * Make better decisions for AUTO in nightmode
            self.waveform_night = C.MTK_WAVEFORM_MODE_GLKW16
            self.night_is_reagl = true
            self.waveform_flashnight = C.MTK_WAVEFORM_MODE_GCK16
            self.setSwipeAnimations = self._MTK_SetSwipeAnimations
            self.setSwipeDirection = self._MTK_SetSwipeDirection
        end

        -- Keep our data structures around, and setup constants
        if self.mech_refresh == refresh_k51 then
            self.update_data = ffi.new("struct mxcfb_update_data")
            -- TEMP_USE_PAPYRUS on Touch/PW1, TEMP_USE_AUTO on PW2 (same value in both cases, 0x1001)
            self.update_data.temp = C.TEMP_USE_AUTO
        elseif self.mech_refresh == refresh_zelda then
            self.update_data = ffi.new("struct mxcfb_update_data_zelda")
            self.update_data.temp = C.TEMP_USE_AMBIENT
        elseif self.mech_refresh == refresh_rex then
            self.update_data = ffi.new("struct mxcfb_update_data_rex")
            self.update_data.temp = C.TEMP_USE_AMBIENT
        elseif self.mech_refresh == refresh_mtk then
            self.update_data = ffi.new("struct mxcfb_update_data_mtk")
            self.update_data.temp = C.TEMP_USE_AMBIENT
            -- The stock reader uses 12. valid values are 1 - 60
            self.update_data.swipe_data.steps = 12
        end
        if self.mech_wait_update_complete == kindle_pearl_mxc_wait_for_update_complete then
            self.marker_data = ffi.new("uint32_t[1]")
        elseif self.mech_wait_update_complete == kindle_carta_mxc_wait_for_update_complete then
            self.marker_data = ffi.new("struct mxcfb_update_marker_data")
            -- NOTE: 0 seems to be a fairly safe assumption for "we don't care about collisions".
            --       On a slightly related note, the EPDC_FLAG_TEST_COLLISION flag is for dry-run collision tests, never set it.
            self.marker_data.collision_test = 0
        end
        if self.mech_wait_update_submission == kindle_mxc_wait_for_update_submission then
            self.submission_data = ffi.new("uint32_t[1]")
        end
    elseif self.device:isKobo() then
        require("ffi/mxcfb_kobo_h")

        self.mech_refresh = refresh_kobo
        self.mech_wait_update_complete = kobo_mxc_wait_for_update_complete

        self.waveform_a2 = C.WAVEFORM_MODE_A2
        self.waveform_fast = C.WAVEFORM_MODE_DU
        self.waveform_ui = C.WAVEFORM_MODE_AUTO
        self.waveform_flashui = self.waveform_ui
        self.waveform_full = C.WAVEFORM_MODE_GC16
        self.waveform_partial = C.WAVEFORM_MODE_AUTO
        self.waveform_night = C.WAVEFORM_MODE_GC16
        self.waveform_flashnight = self.waveform_night
        self.night_is_reagl = false

        if self.device:isREAGL() then
            self.waveform_reagl = C.WAVEFORM_MODE_REAGLD
            self.waveform_partial = self.waveform_reagl
            self.waveform_fast = C.WAVEFORM_MODE_DU -- Mainly menu HLs, compare to Kindle's use of AUTO or DU also in these instances ;).
        end

        -- NOTE: There's a fun twist to Mark 7 devices:
        --       They do use GLR16 update modes (i.e., REAGL), but they do NOT need/do the PARTIAL -> FULL trick...
        --       We handle that by NOT setting waveform_reagl (so _isREAGLWaveFormMode never matches), and just customizing waveform_partial.
        --       Nickel doesn't wait for completion of previous markers on those PARTIAL GLR16, so that's enough to keep our heuristics intact,
        --       while still doing the right thing everywhere ;).
        --       Turns out there's a good reason for that: the EPDC will fence REAGL updates internally (possibly via the PxP).
        --       This makes interaction between partial and other modes slightly finicky in practice in some corner-cases,
        --       (c.f., the SkimTo/Button widgets workaround where we batch a button's 'fast' highlight with the reader's 'partial',
        --       and then fence *that batch* manually to avoid the (REAGL) 'partial' being delayed by the button's 'fast' highlight).
        if self.device:isMk7() then
            self.mech_refresh = refresh_kobo_mk7
            if self.device:hasReliableMxcWaitFor() then
                self.mech_wait_update_complete = kobo_mk7_mxc_wait_for_update_complete
            else
                -- Funky variant that will do this in pairs, like Nickel itself...
                -- Spoiler alert: doesn't actually prevent timeouts.
                -- Which means this branch and imp is basically for show,
                -- as it'll be replaced by stub_mxc_wait_for_update_complete below...
                self.mech_wait_update_complete = kobo_mk7_unreliable_mxc_wait_for_update_complete
            end

            self.waveform_partial = C.WAVEFORM_MODE_REAGL
            self.waveform_fast = C.WAVEFORM_MODE_DU -- A2 is much more prone to artifacts on Mk. 7 than before, because everything's faster.
                                                    -- Nickel sometimes uses DU, but never w/ the MONOCHROME flag, so, do the same.
                                                    -- Plus, DU + MONOCHROME + INVERT is much more prone to the Mk. 7 EPDC bug where some/all
                                                    -- EPDC flags just randomly go bye-bye...
        end

        if self.device:hasEclipseWfm() then
            self.waveform_night = C.WAVEFORM_MODE_GLKW16
            self.waveform_flashnight = C.WAVEFORM_MODE_GCK16
        end

        -- If the (NXP) device has a sysfs knob to control the EPDC power, use it
        if lfs.attributes("/sys/class/graphics/fb0/power_state", "mode") ~= nil then
            -- Conditional, because it's only available on some of the later boards with NXP SoCs (ca., Mk. 9 & 10)...
            -- (Usually, those boards are flagged !hasReliableMxcWaitFor...)
            self.mech_poweron = kobo_nxp_wakeup_epdc
        end

        -- Do the right thing on MTK, which exposes fairly similar APIs.
        if self.device:isMTK() then
            self.mech_refresh = refresh_kobo_mtk
            self.mech_wait_update_complete = kobo_mtk_wait_for_update_complete
            -- FIXME: Enable this, assuming it behaves...
            --self.mech_wait_update_submission = kobo_mtk_wait_for_update_submission

            self.waveform_a2 = C.HWTCON_WAVEFORM_MODE_A2
            self.waveform_fast = C.HWTCON_WAVEFORM_MODE_DU
            self.waveform_ui = C.HWTCON_WAVEFORM_MODE_AUTO
            self.waveform_flashui = self.waveform_ui
            self.waveform_full = C.HWTCON_WAVEFORM_MODE_GC16
            -- REAGL is *always* available
            self.waveform_partial = C.HWTCON_WAVEFORM_MODE_GLR16
            -- Eclipse waveform modes are *always* available
            self.waveform_night = C.HWTCON_WAVEFORM_MODE_GLKW16
            self.waveform_flashnight = C.HWTCON_WAVEFORM_MODE_GCK16

            self.mech_poweron = kobo_mtk_wakeup_epdc
        end

        local bypass_wait_for = self:getMxcWaitForBypass()
        -- If the user (or a device cap check) requested bypassing the MXCFB_WAIT_FOR_UPDATE_COMPLETE ioctls, do so.
        if bypass_wait_for then
            -- The stub implementation just fakes this ioctl by sleeping for a tiny amount of time instead... :/.
            self.mech_wait_update_complete = stub_mxc_wait_for_update_complete
        end

        -- Keep our data structures around, and setup constants
        if self.mech_refresh == refresh_kobo then
            self.update_data = ffi.new("struct mxcfb_update_data_v1_ntx")
            self.update_data.alt_buffer_data.virt_addr = nil
            -- TEMP_USE_AMBIENT, not that there was ever any other choice on Kobo...
            self.update_data.temp = C.TEMP_USE_AMBIENT
        elseif self.mech_refresh == refresh_kobo_mk7 then
            self.update_data = ffi.new("struct mxcfb_update_data_v2")
            -- TEMP_USE_AMBIENT, not that there was ever any other choice on Kobo...
            self.update_data.temp = C.TEMP_USE_AMBIENT
        elseif self.mech_refresh == refresh_kobo_mtk then
            self.update_data = ffi.new("struct hwtcon_update_data")
        end
        if self.mech_wait_update_complete == kobo_mxc_wait_for_update_complete or self.mech_wait_update_complete == kobo_mtk_wait_for_update_complete then
            self.marker_data = ffi.new("uint32_t[1]")
        elseif self.mech_wait_update_complete == kobo_mk7_mxc_wait_for_update_complete or self.mech_wait_update_complete == kobo_mk7_unreliable_mxc_wait_for_update_complete then
            self.marker_data = ffi.new("struct mxcfb_update_marker_data")
            -- NOTE: 0 seems to be a fairly safe assumption for "we don't care about collisions".
            --       On a slightly related note, the EPDC_FLAG_TEST_COLLISION flag is for dry-run collision tests, never set it.
            self.marker_data.collision_test = 0
        end
        if self.mech_wait_update_submission == kobo_mtk_wait_for_update_submission then
            self.submission_data = ffi.new("uint32_t[1]")
        end
    elseif self.device:isPocketBook() then
        require("ffi/mxcfb_pocketbook_h")

        self.mech_refresh = refresh_pocketbook
        self.mech_wait_update_complete = pocketbook_mxc_wait_for_update_complete

        self.waveform_a2 = C.WAVEFORM_MODE_A2
        self.wf_level_max = 3
        local level = self:getWaveformLevel()
        -- Level 0 is most conservative.
        -- This is what inkview does on all platforms.
        -- Slow (>150ms on B288 Carta).
        if level == 0 then
            self.waveform_fast = C.WAVEFORM_MODE_GC16
            self.waveform_partial = C.WAVEFORM_MODE_GC16
        elseif level == 1 then
            self.waveform_fast = C.WAVEFORM_MODE_DU
            self.waveform_partial = C.WAVEFORM_MODE_GC16
        elseif level == 2 then
            self.waveform_fast = C.WAVEFORM_MODE_DU
            self.waveform_partial = self:isB288() and C.WAVEFORM_MODE_GS16 or C.WAVEFORM_MODE_GC16
        -- Level 3 is most aggressive.
        -- Fast (>80ms on B288 Carta), but flickers and may be buggy.
        elseif level == 3 then
            self.waveform_fast = C.WAVEFORM_MODE_DU
            self.waveform_partial = C.WAVEFORM_MODE_GL16
        end

        self.waveform_ui = self.waveform_partial
        self.waveform_flashui = C.WAVEFORM_MODE_GC16
        self.waveform_full = C.WAVEFORM_MODE_GC16
        self.waveform_night = C.WAVEFORM_MODE_GC16
        self.waveform_flashnight = self.waveform_night
        self.night_is_reagl = false

        -- Keep our data structures around, and setup constants
        self.update_data = ffi.new("struct mxcfb_update_data")
        -- NOTE: We update temp at runtime on PB
        self.marker_data = ffi.new("struct mxcfb_update_marker_data")
        -- NOTE: 0 seems to be a fairly safe assumption for "we don't care about collisions".
        --       On a slightly related note, the EPDC_FLAG_TEST_COLLISION flag is for dry-run collision tests, never set it.
        self.marker_data.collision_test = 0
    elseif self.device:isRemarkable() then
        require("ffi/mxcfb_remarkable_h")

        self.mech_refresh = refresh_remarkable
        self.mech_wait_update_complete = remarkable_mxc_wait_for_update_complete

        self.waveform_a2 = C.WAVEFORM_MODE_A2
        self.waveform_fast = C.WAVEFORM_MODE_DU
        self.waveform_ui = C.WAVEFORM_MODE_GL16
        self.waveform_flashui = C.WAVEFORM_MODE_GC16
        self.waveform_full = C.WAVEFORM_MODE_GC16
        self.waveform_partial = C.WAVEFORM_MODE_GL16
        self.waveform_night = C.WAVEFORM_MODE_GC16
        self.waveform_flashnight = self.waveform_night
        self.night_is_reagl = false

        -- Keep our data structures around
        self.update_data = ffi.new("struct mxcfb_update_data")
        -- NOTE: We update temp at runtime on rM
        self.marker_data = ffi.new("struct mxcfb_update_marker_data")
        -- NOTE: 0 seems to be a fairly safe assumption for "we don't care about collisions".
        --       On a slightly related note, the EPDC_FLAG_TEST_COLLISION flag is for dry-run collision tests, never set it.
        self.marker_data.collision_test = 0
    elseif self.device:isSonyPRSTUX() then
        require("ffi/mxcfb_sony_h")

        self.mech_refresh = refresh_sony_prstux
        self.mech_wait_update_complete = sony_prstux_mxc_wait_for_update_complete

        self.waveform_a2 = C.WAVEFORM_MODE_A2
        self.waveform_fast = C.WAVEFORM_MODE_DU
        self.waveform_ui = C.WAVEFORM_MODE_AUTO
        self.waveform_flashui = self.waveform_ui
        self.waveform_full = C.WAVEFORM_MODE_GC16
        self.waveform_partial = C.WAVEFORM_MODE_AUTO
        self.waveform_night = C.WAVEFORM_MODE_GC16
        self.waveform_flashnight = self.waveform_night
        self.night_is_reagl = false

        -- Keep our data structures around, and setup constants
        self.update_data = ffi.new("struct mxcfb_update_data")
        self.update_data.temp = C.TEMP_USE_AMBIENT
        self.marker_data = ffi.new("uint32_t[1]")
    elseif self.device:isCervantes() then
        require("ffi/mxcfb_cervantes_h")

        self.mech_refresh = refresh_cervantes
        self.mech_wait_update_complete = cervantes_mxc_wait_for_update_complete

        self.waveform_a2 = C.WAVEFORM_MODE_A2
        self.waveform_fast = C.WAVEFORM_MODE_DU
        self.waveform_ui = C.WAVEFORM_MODE_AUTO
        self.waveform_flashui = self.waveform_ui
        self.waveform_full = C.WAVEFORM_MODE_GC16
        self.waveform_partial = C.WAVEFORM_MODE_AUTO
        self.waveform_night = C.WAVEFORM_MODE_GC16
        self.waveform_flashnight = self.waveform_night
        self.night_is_reagl = false

        -- Keep our data structures around, and setup constants
        self.update_data = ffi.new("struct mxcfb_update_data")
        self.update_data.temp = C.TEMP_USE_AMBIENT
        self.marker_data = ffi.new("uint32_t[1]")
    else
        error("unknown device type")
    end
end

return require("ffi/framebuffer_linux"):extend(framebuffer)
