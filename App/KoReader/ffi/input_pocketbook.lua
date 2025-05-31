local ffi = require("ffi")
local C = ffi.C
local rt = ffi.load("librt.so")
local inkview = ffi.load("inkview")
local util = require("ffi/util")

local bit = require("bit")
local band = bit.band

require("ffi/posix_h")
require("ffi/linux_input_h")
require("ffi/inkview_h")

-- InkView 4.x doesn't have the polling APIs, so inkview-compat.c
-- emulates those in a semaphore step-locked thread.
local compat, compat2 = inkview, inkview
if not pcall(function() local _ = inkview.PrepareForLoop end) then
    compat = ffi.load("inkview-compat")
    compat2 = compat
elseif not pcall(function() local _ = inkview.GetTouchInfoI end) then
    compat2 = ffi.load("inkview-compat")
end

local input = {}

local ts
-- Create new 'ts' with current timestamp.
-- The value is then shared by all events received/emulated at the same point in time.
local function updateTimestamp()
    local sec, usec = util.gettime()
    ts = { sec = sec, usec = usec }
    return ts
end

local eventq
-- Make emulated event and add it to the queue (ts presumed updated beforehand)
local function genEmuEvent(t, c, v)
    table.insert(eventq, {
        type = tonumber(t),
        code = tonumber(c),
        value = tonumber(v) or v,
        time = ts,
    })
end

-- For debug logging
local DEBUG
local logger
local pb_event_map = {
    [C.EVT_INIT] = "EVT_INIT",
    [C.EVT_EXIT] = "EVT_EXIT",
    [C.EVT_SHOW] = "EVT_SHOW",
    [C.EVT_REPAINT] = "EVT_REPAINT",
    [C.EVT_HIDE] = "EVT_HIDE",
    [C.EVT_KEYDOWN] = "EVT_KEYDOWN",
    [C.EVT_KEYPRESS] = "EVT_KEYPRESS",
    [C.EVT_KEYUP] = "EVT_KEYUP",
    [C.EVT_KEYRELEASE] = "EVT_KEYRELEASE",
    [C.EVT_KEYREPEAT] = "EVT_KEYREPEAT",
    [C.EVT_POINTERUP] = "EVT_POINTERUP",
    [C.EVT_POINTERDOWN] = "EVT_POINTERDOWN",
    [C.EVT_POINTERMOVE] = "EVT_POINTERMOVE",
    [C.EVT_POINTERLONG] = "EVT_POINTERLONG",
    [C.EVT_POINTERHOLD] = "EVT_POINTERHOLD",
    [C.EVT_POINTERDRAG] = "EVT_POINTERDRAG",
    [C.EVT_POINTERCANCEL] = "EVT_POINTERCANCEL",
    [C.EVT_ORIENTATION] = "EVT_ORIENTATION",
    [C.EVT_FOCUS] = "EVT_FOCUS",
    [C.EVT_UNFOCUS] = "EVT_UNFOCUS",
    [C.EVT_ACTIVATE] = "EVT_ACTIVATE",
    [C.EVT_MTSYNC] = "EVT_MTSYNC",
    [C.EVT_TOUCHUP] = "EVT_TOUCHUP",
    [C.EVT_TOUCHDOWN] = "EVT_TOUCHDOWN",
    [C.EVT_TOUCHMOVE] = "EVT_TOUCHMOVE",
    [C.EVT_QN_MOVE] = "EVT_QN_MOVE",
    [C.EVT_QN_RELEASE] = "EVT_QN_RELEASE",
    [C.EVT_QN_BORDER] = "EVT_QN_BORDER",
    [C.EVT_SNAPSHOT] = "EVT_SNAPSHOT",
    [C.EVT_FSINCOMING] = "EVT_FSINCOMING",
    [C.EVT_FSCHANGED] = "EVT_FSCHANGED",
    [C.EVT_MP_STATECHANGED] = "EVT_MP_STATECHANGED",
    [C.EVT_MP_TRACKCHANGED] = "EVT_MP_TRACKCHANGED",
    [C.EVT_PREVPAGE] = "EVT_PREVPAGE",
    [C.EVT_NEXTPAGE] = "EVT_NEXTPAGE",
    [C.EVT_OPENDIC] = "EVT_OPENDIC",
    [C.EVT_CONTROL_PANEL_ABOUT_TO_OPEN] = "EVT_CONTROL_PANEL_ABOUT_TO_OPEN",
    [C.EVT_PANEL_BLUETOOTH_A2DP] = "EVT_PANEL_BLUETOOTH_A2DP",
    [C.EVT_TAB] = "EVT_TAB",
    [C.EVT_PANEL] = "EVT_PANEL",
    [C.EVT_PANEL_ICON] = "EVT_PANEL_ICON",
    [C.EVT_PANEL_TEXT] = "EVT_PANEL_TEXT",
    [C.EVT_PANEL_PROGRESS] = "EVT_PANEL_PROGRESS",
    [C.EVT_PANEL_MPLAYER] = "EVT_PANEL_MPLAYER",
    [C.EVT_PANEL_USBDRIVE] = "EVT_PANEL_USBDRIVE",
    [C.EVT_PANEL_NETWORK] = "EVT_PANEL_NETWORK",
    [C.EVT_PANEL_CLOCK] = "EVT_PANEL_CLOCK",
    [C.EVT_PANEL_BLUETOOTH] = "EVT_PANEL_BLUETOOTH",
    [C.EVT_PANEL_TASKLIST] = "EVT_PANEL_TASKLIST",
    [C.EVT_PANEL_OBREEY_SYNC] = "EVT_PANEL_OBREEY_SYNC",
    [C.EVT_PANEL_SETREADINGMODE] = "EVT_PANEL_SETREADINGMODE",
    [C.EVT_PANEL_SETREADINGMODE_INVERT] = "EVT_PANEL_SETREADINGMODE_INVERT",
    [C.EVT_PANEL_FRONT_LIGHT] = "EVT_PANEL_FRONT_LIGHT",
    [C.EVT_GLOBALREQUEST] = "EVT_GLOBALREQUEST",
    [C.EVT_GLOBALACTION] = "EVT_GLOBALACTION",
    [C.EVT_FOREGROUND] = "EVT_FOREGROUND",
    [C.EVT_BACKGROUND] = "EVT_BACKGROUND",
    [C.EVT_SUBTASKCLOSE] = "EVT_SUBTASKCLOSE",
    [C.EVT_CONFIGCHANGED] = "EVT_CONFIGCHANGED",
    [C.EVT_SAVESTATE] = "EVT_SAVESTATE",
    [C.EVT_OBREEY_CONFIG_CHANGED] = "EVT_OBREEY_CONFIG_CHANGED",
    [C.EVT_SDIN] = "EVT_SDIN",
    [C.EVT_SDOUT] = "EVT_SDOUT",
    [C.EVT_BT_RXCOMPLETE] = "EVT_BT_RXCOMPLETE",
    [C.EVT_BT_TXCOMPLETE] = "EVT_BT_TXCOMPLETE",
    [C.EVT_SYNTH_ENDED] = "EVT_SYNTH_ENDED",
    [C.EVT_DIC_CLOSED] = "EVT_DIC_CLOSED",
    [C.EVT_SHOW_KEYBOARD] = "EVT_SHOW_KEYBOARD",
    [C.EVT_TEXTCLEAR] = "EVT_TEXTCLEAR",
    [C.EVT_EXT_KB] = "EVT_EXT_KB",
    [C.EVT_LETTER] = "EVT_LETTER",
    [C.EVT_CALLBACK] = "EVT_CALLBACK",
    [C.EVT_SCANPROGRESS] = "EVT_SCANPROGRESS",
    [C.EVT_STOPSCAN] = "EVT_STOPSCAN",
    [C.EVT_STARTSCAN] = "EVT_STARTSCAN",
    [C.EVT_SCANSTOPPED] = "EVT_SCANSTOPPED",
    [C.EVT_POSTPONE_TIMED_POWEROFF] = "EVT_POSTPONE_TIMED_POWEROFF",
    [C.EVT_FRAME_ACTIVATED] = "EVT_FRAME_ACTIVATED",
    [C.EVT_FRAME_DEACTIVATED] = "EVT_FRAME_DEACTIVATED",
    [C.EVT_READ_PROGRESS_CHANGED] = "EVT_READ_PROGRESS_CHANGED",
    [C.EVT_DUMP_BITMAPS_DEBUG_INFO] = "EVT_DUMP_BITMAPS_DEBUG_INFO",
    [C.EVT_NET_CONNECTED] = "EVT_NET_CONNECTED",
    [C.EVT_NET_DISCONNECTED] = "EVT_NET_DISCONNECTED",
    [C.EVT_NET_FOUND_NEW_FW] = "EVT_NET_FOUND_NEW_FW",
    [C.EVT_SYNTH_POSITION] = "EVT_SYNTH_POSITION",
}

-- Keep track of all the active contact points.
-- *hash*, key is a contact *id* (i.e., its slot number),
-- value is a boolean, denoting whether the contact is currently down (true), up (false) or inactive (nil).
-- Returns true if the state actually changed.
local contacts = {}
local function setContactDown(slot, down)
    if contacts[slot] ~= down then
        contacts[slot] = down
        return true
    end

    return false
end

-- Translate event from inkview EVT_* into emulated linux evdev events
local function translateEvent(t, par1, par2)
    -- Much like Input does, detail what we catch when debug logging is enabled
    if DEBUG.is_on then
        logger.dbg(string.format("PB event => %d (%s), par1: %s, par2: %s", t, pb_event_map[t], par1, par2))
    end

    if not eventq then
        -- Caught something post closeAll? (We're an InkView callback, remember).
        return 0
    end

    if t == C.EVT_INIT then
        inkview.SetPanelType(C.PANEL_DISABLED)
    elseif t == C.EVT_POINTERDOWN then
        -- Refresh the timestamp genEmuEvent will use
        updateTimestamp()

        genEmuEvent(C.EV_ABS, C.ABS_MT_SLOT, 0)
        if setContactDown(0, true) then
            genEmuEvent(C.EV_ABS, C.ABS_MT_TRACKING_ID, 0)
        end
        genEmuEvent(C.EV_ABS, C.ABS_MT_POSITION_X, par1)
        genEmuEvent(C.EV_ABS, C.ABS_MT_POSITION_Y, par2)
        genEmuEvent(C.EV_SYN, C.SYN_REPORT, 0)
    elseif t == C.EVT_MTSYNC then
        updateTimestamp()

        -- par2 is the contact count for the *current* frame (amount may fluctuate before the final lift at 0).
        if par2 > 1 then
            -- NOTE: Never query slot 0, we rely on the POINTER* events for it instead,
            --       as we don't need an extra function call to get at the coordinates with those.
            -- par1 is the index to the base pointer for the current frame, as InkView seems to be keeping a number of past frames in memory...
            local mtp = compat2.GetTouchInfoI(par1)
            for i = 1, par2 - 1 do
                -- NOTE: We're making a very shaky assumption that the index here roughly translates to a *stable* slot number,
                --       and as such that POINTER events are always at 0, which is why we're skipping it...
                local mt = mtp + i
                -- GetTouchInfoI may fail or return a !active contact, try to handle it to avoid spitting out a (0, 0) contact...
                -- NOTE: That does not seem to be indicative of a contact lift,
                --       which means we have no way of detecting a lift on slot > 0 until *all* contacts are lifted...
                if mt.active ~= 0 then
                    genEmuEvent(C.EV_ABS, C.ABS_MT_SLOT, i)
                    if setContactDown(i, true) then
                        genEmuEvent(C.EV_ABS, C.ABS_MT_TRACKING_ID, i)
                    end
                    genEmuEvent(C.EV_ABS, C.ABS_MT_POSITION_X, mt.x)
                    genEmuEvent(C.EV_ABS, C.ABS_MT_POSITION_Y, mt.y)
                end
            end
            genEmuEvent(C.EV_SYN, C.SYN_REPORT, 0)
        elseif par2 == 0 then
            local stuff_happened = false
            for slot, down in pairs(contacts) do
                if down then
                    genEmuEvent(C.EV_ABS, C.ABS_MT_SLOT, slot)
                    genEmuEvent(C.EV_ABS, C.ABS_MT_TRACKING_ID, -1)
                    setContactDown(slot, false)

                    stuff_happened = true
                end
            end
            -- Only send a report if we actually generated lift events...
            if stuff_happened then
                genEmuEvent(C.EV_SYN, C.SYN_REPORT, 0)
            end
        end
    elseif t == C.EVT_POINTERMOVE then
        if contacts[0] then
            updateTimestamp()

            genEmuEvent(C.EV_ABS, C.ABS_MT_SLOT, 0)
            genEmuEvent(C.EV_ABS, C.ABS_MT_POSITION_X, par1)
            genEmuEvent(C.EV_ABS, C.ABS_MT_POSITION_Y, par2)
            genEmuEvent(C.EV_SYN, C.SYN_REPORT, 0)
        end
    elseif t == C.EVT_POINTERUP then
        if contacts[0] then
            updateTimestamp()

            genEmuEvent(C.EV_ABS, C.ABS_MT_SLOT, 0)
            genEmuEvent(C.EV_ABS, C.ABS_MT_TRACKING_ID, -1)
            genEmuEvent(C.EV_SYN, C.SYN_REPORT, 0)
            setContactDown(0, false)
        end
    elseif t == C.EVT_KEYDOWN then
        updateTimestamp()

        genEmuEvent(C.EV_KEY, par1, 1)
    elseif t == C.EVT_KEYREPEAT then
        updateTimestamp()

        genEmuEvent(C.EV_KEY, par1, 2)
    elseif t == C.EVT_KEYUP then
        updateTimestamp()

        genEmuEvent(C.EV_KEY, par1, 0)
    elseif t == C.EVT_BACKGROUND or t == C.EVT_FOREGROUND
        or t == C.EVT_SHOW or t == C.EVT_HIDE
        or t == C.EVT_EXIT then
        updateTimestamp()

        -- Handle those as MiscEvent as this makes it easy to return a string directly,
        -- which can be used in uimanager.lua as an event_handler index.
        genEmuEvent(C.EV_MSC, t, 0)
    elseif t == C.EVT_ORIENTATION then
        updateTimestamp()

        -- Translate those to our own EV_MSC:MSC_GYRO proto
        if par1 == 0 then
            -- i.e., UR
            genEmuEvent(C.EV_MSC, C.MSC_GYRO, C.DEVICE_ROTATED_UPRIGHT)
        elseif par1 == 2 then
            -- i.e., CW
            genEmuEvent(C.EV_MSC, C.MSC_GYRO, C.DEVICE_ROTATED_CLOCKWISE)
        elseif par1 == 3 then
            -- i.e., UD
            genEmuEvent(C.EV_MSC, C.MSC_GYRO, C.DEVICE_ROTATED_UPSIDE_DOWN)
        elseif par1 == 1 then
            -- i.e., CCW
            genEmuEvent(C.EV_MSC, C.MSC_GYRO, C.DEVICE_ROTATED_COUNTER_CLOCKWISE)
        end
    end
    return 0
end

local raw_keymap -- [EV_KEY] = "Action" supplied by frontend
local poll_fds, poll_fds_count = nil, 0
function input:open()
    -- Don't do this at home, kids, these belong to front.
    DEBUG = require("dbg")
    logger = require("logger")

    eventq = {}
    -- Have all the necessary bits to run in raw mode without inkview interfering
    poll_fds = nil
    if self.raw_input then
        local max_fds = 20
        raw_keymap = self.raw_input.keymap
        poll_fds = ffi.new("struct pollfd[?]", max_fds)

        -- Open the monitor queue. We could technically live without it on older firmwares
        -- that don't have it, but I'm not sure how events are meant to be consumed on there
        -- to prevent stall, so for the time being we bail when we don't see it.
        local hwinput = rt.mq_open("/hwevent", C.O_RDONLY+C.O_NONBLOCK)
        assert(hwinput >= 0, "No /hwevent, probably too old firmware")
        poll_fds[0].fd = hwinput
        poll_fds[0].events = C.POLLIN
        poll_fds_count = 1

        -- Open the raw input devices.
        -- You must chmod those to be readable by non-root somehow (or run as root)
        for i=1, max_fds-1 do
            local input_dev = "/dev/input/event"..tostring(i)
            local fd = C.open(input_dev, bit.bor(C.O_RDONLY, C.O_NONBLOCK, C.O_CLOEXEC))
            if fd >= 0 then
                poll_fds[poll_fds_count].fd = fd
                poll_fds[poll_fds_count].events = C.POLLIN
                poll_fds_count = poll_fds_count + 1
            end
        end
        assert(poll_fds_count > 1, "Need access to /dev/input devices")

        -- This is only small part of what OpenScreen() does, namely map the shared state
        -- memory segment, and setup some touch/g info. Most of inkview API can run with just this
        -- in spite of us never setting up the event loop or screen canvas.
        inkview.hw_init()
        inkview.iv_update_orientation(0)
        inkview.iv_setup_touchpanel()
        inkview.iv_setup_gsensor()
        return
    end

    -- This enables the inkview orientation events to be sent to translateEvent
    C.setenv("SUPPORT_EVT_ORIENTATION", "YES", 1)

    -- Initialize inkview ordinarily.
    compat.PrepareForLoop(translateEvent)
end

-- CLOCK_REALTIME value, in µs
local function now()
    local s, u = util.gettime()
    return tonumber(s) * 1000000.0 + u
end

local evmsg = ffi.new("struct input_event[1]")
local evmsg_len = ffi.sizeof(evmsg)
local hwmsg = ffi.new("struct hw_event_s[1]")
local hwmsg_len = ffi.sizeof(hwmsg)

local function convertEvent(msg)
    return {
        -- Hmm, this is a little bit silly. The types are *almost* identical, except this.
        time = { sec = msg[0].time.tv_sec, usec = msg[0].time.tv_usec },
        type = msg[0].type,
        code = msg[0].code,
        value = msg[0].value,
    }
end

local is_active = false
local next_sleep = 0
local function waitForEventRaw(timeout)
    local expire = now() + timeout
    while true do
        -- Reset event queue
        eventq = {}

        local active = inkview.IsTaskActive() ~= 0
        -- Focus in/out transition, emit a synthetic event.
        if active ~= is_active then
            -- Avoid going to sleep during state transitions,
            -- so as to not accidentaly go sleeping mid fb refresh.
            next_sleep = now() + 10 * 1000 * 1000
            is_active = active
            return true, {
                type = C.EV_MSC,
                code = active and C.EVT_SHOW or C.EVT_HIDE,
                value = 0,
                time = updateTimestamp(),
            }
        end
        -- We have got sleepmode ("autostandby") requested by frontend.
        -- We must be a "properly" foregroun running to do this - no keylock (zzzz), and IsTaskActive must be true.
        -- In any other case, the monitor has the hot potato to manage sleep states
        if active and inkview.hw_get_keylock() == 0 and inkview.GetSleepmode() > 0 and now() > next_sleep then
            local before = now()
            -- This function may, or may not suspend the device until RTC in specified time,
            -- or GPIO (touch/button/Gsensor) fires. We make RTC wake up every 3 minutes to give
            -- autosuspend.koplugin timers a chance to kick in.
            inkview.GoSleep(180 * 1000, 0)
            -- If the system got suspended (T delta > 100ms), avoid sleeping for a bit again.
            -- We need to give chance a to monitor to flip our active / keylock flags if those have have changed.
            -- Without this, GoSleep could step on monitor while its doing the in/out sleep blur animation.
            if (now() - before) > 100 * 1000 then
                next_sleep = now() + 100 * 1000
            end
        end

        local remain = expire - now()
        if remain < 0 then
            -- Timed out
            return false, C.ETIME
        end

        local ms = math.max(math.min(remain / 1000, 1000), 20)
        poll_fds[0].events = is_active and C.POLLIN or 0
        for i=0, poll_fds_count-1 do
            poll_fds[i].revents = 0
        end
        local res = C.poll(poll_fds, poll_fds_count, ms)
        if res < 0 then
            return false, ffi.errno()
        end

        --- @note: No poll timeout handling?
        --         e.g., if res == 0 then return false, C.ETIME end

        -- Message from monitor. This sendss us both touch and key events, but not in a format
        -- thats particularly useful. Keys are nice as they have symbolic names already, but
        -- touch events are utter mess. In any case, this queue *must* be consumed, lest otherwise
        -- monitor would spam queued events to whaetever else gets focus after us.
        if band(poll_fds[0].revents, C.POLLIN) ~= 0 then
            updateTimestamp() -- single 'ts' copy for genEmuEvent inside the loop
            while rt.mq_receive(poll_fds[0].fd, ffi.cast("char*", hwmsg), hwmsg_len, nil) > 0 do
                local m = hwmsg[0]
                -- If there's no raw keymapping, emit this one instead
                if (m.type == C.EVT_KEYDOWN or m.type == C.EVT_KEYUP or m.type == C.EVT_KEYREPEAT) and not raw_keymap then
                    genEmuEvent(m.type, m.common.par1, m.common.par2)
                end
            end
        end

        -- Read all /dev/input pipes. We don't care which is which (for instance PB740 has 2
        -- input keyboards for measly 4 buttons!). So we simply discern by event code some of which is
        -- EV_KEY/EV_ABS/EV_SYN. One of the pipes is even BT/OTG keyboard, so typing on it works too.
        for i=1, poll_fds_count-1 do
            if band(poll_fds[i].revents, C.POLLIN) ~= 0 then
                while C.read(poll_fds[i].fd, evmsg, evmsg_len) == evmsg_len do
                    if is_active then
                        table.insert(eventq, convertEvent(evmsg))
                    end
                end
            end
        end
        if #eventq > 0 then
            return true, eventq
        end
    end
end

function input.waitForEvent(sec, usec)
    -- TimeVal's :tousecs if we were passed one to begin with, otherwise => 2s
    --- @note: This is unlike every other platform, where the fallback is an infinite timeout!
    local timeout = sec and math.floor(sec * 1000000 + usec + 0.5) or 2000000
    assert(eventq, "waitForEvent() invoked after device shutdown")
    if poll_fds then
        -- This variant uses low-level input I/O bypassing inkview for that entirely
        return waitForEventRaw(timeout)
    end
    local expire = now() + timeout
    while expire > now() do
        -- Reset event queue
        eventq = {}
        -- About ProcessEventLoop():
        -- When events are pending, translateEvent() cb is called for each here (it remembers what we've announced in PrepareForLoop).
        -- Our callback then queues whatever events it collects, translating to linux evinput while doing so.
        -- The call holds for 20ms and returns control once no further input is seen during that time. If iv_sleepmode is 1 however, and
        -- no input is seen for >2 seconds (it keeps track across invocations), the call will perform full OS suspend ("autostandby").
        compat.ProcessEventLoop()
        if #eventq > 0 then
            return true, eventq
        end
    end
    -- Timed out
    return false, C.ETIME
end

function input.fakeTapInput() end

function input.closeAll()
    eventq = nil
    if poll_fds ~= nil then
        rt.mq_close(poll_fds[0].fd)
        for i=1, poll_fds_count-1 do
            C.close(poll_fds[i].fd)
        end
        poll_fds = nil
        inkview.hw_close()
    else
        compat.ClearOnExit()
    end
end

return input
