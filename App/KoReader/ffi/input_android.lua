local ffi = require("ffi")
local bit = require("bit")
local C = ffi.C

local android = require("android")
require("ffi/posix_h")
require("ffi/linux_input_h")

local input = {
    -- to trigger refreshes for certain Android framework events:
    device = nil,
}

function input.open()
end

local inputQueue = {}

local function genInputTimeval(ts)
    local timev = { sec = 0, usec = 0 }
    if ts then
        -- If we've got one, trust the native event's timestamp, they're guaranteed to be in the CLOCK_MONOTONIC timebase.
        -- ns to µs
        -- NOTE: Unlike the Java APIs, this is in nanoseconds!
        --       c.f., https://developer.android.com/ndk/reference/group/input#amotionevent_geteventtime
        local us = ts / 1000
        -- TimeVal, how I miss thee...
        timev.sec = math.floor(tonumber(us / 1000000))
        timev.usec = tonumber(us % 1000000)
    else
        -- Otherwise, synthetize one in the same time scale.
        -- TimeVal probably ought to be in base...
        local timespec = ffi.new("struct timespec")
        C.clock_gettime(C.CLOCK_MONOTONIC, timespec)
        timev.sec = tonumber(timespec.tv_sec)
        -- ns to µs
        timev.usec = math.floor(tonumber(timespec.tv_nsec / 1000))
    end

    return timev
end

local function genEmuEvent(evtype, code, value, timev, ts)
    local ev = {
        type = tonumber(evtype),
        code = tonumber(code),
        value = tonumber(value),
        time = timev or genInputTimeval(ts),
    }
    table.insert(inputQueue, ev)
end

-- Keep track of all the active pointers in the current gesture.
-- *hash*, key is a pointer *id* (i.e., its slot number),
-- value is a boolean, denoting whether the pointer is currently down (e.g., in contact) (true), up (false) or inactive (nil).
local pointers = {}
local function setPointerDown(slot, down)
    if pointers[slot] ~= down then
        pointers[slot] = down
    end
end

local function genTouchDownEvent(event, slot, index)
    local x = android.lib.AMotionEvent_getX(event, index)
    local y = android.lib.AMotionEvent_getY(event, index)
    local timev = genInputTimeval(android.lib.AMotionEvent_getEventTime(event))
    genEmuEvent(C.EV_ABS, C.ABS_MT_SLOT, slot, timev)
    genEmuEvent(C.EV_ABS, C.ABS_MT_TRACKING_ID, slot, timev)
    genEmuEvent(C.EV_ABS, C.ABS_MT_POSITION_X, x, timev)
    genEmuEvent(C.EV_ABS, C.ABS_MT_POSITION_Y, y, timev)
    genEmuEvent(C.EV_SYN, C.SYN_REPORT, 0, timev)
end

local function genTouchUpEvent(event, slot, index)
    local x = android.lib.AMotionEvent_getX(event, index)
    local y = android.lib.AMotionEvent_getY(event, index)
    local timev = genInputTimeval(android.lib.AMotionEvent_getEventTime(event))
    genEmuEvent(C.EV_ABS, C.ABS_MT_SLOT, slot, timev)
    genEmuEvent(C.EV_ABS, C.ABS_MT_TRACKING_ID, -1, timev)
    genEmuEvent(C.EV_ABS, C.ABS_MT_POSITION_X, x, timev)
    genEmuEvent(C.EV_ABS, C.ABS_MT_POSITION_Y, y, timev)
    genEmuEvent(C.EV_SYN, C.SYN_REPORT, 0, timev)
end

local function genTouchMoveEvent(event, timev, slot, index)
    -- NOTE: May return a float for events w/ subpixel precision.
    local x = android.lib.AMotionEvent_getX(event, index)
    local y = android.lib.AMotionEvent_getY(event, index)
    genEmuEvent(C.EV_ABS, C.ABS_MT_SLOT, slot, timev)
    genEmuEvent(C.EV_ABS, C.ABS_MT_POSITION_X, x, timev)
    genEmuEvent(C.EV_ABS, C.ABS_MT_POSITION_Y, y, timev)
end

local function genEndTouchEvent(event, timev)
    genEmuEvent(C.EV_SYN, C.SYN_REPORT, 0, timev)
end

local function genAndroidCancelEvent(event)
    local timev = genInputTimeval(android.lib.AMotionEvent_getEventTime(event))
    -- We piggyback on this EV_MSC code, because our EV_MSC handler already handles it via Device.input:resetState(),
    -- which is *exactly* what we want to happen ;).
    genEmuEvent(C.EV_MSC, C.APP_CMD_LOST_FOCUS, 42, timev)
end

-- NOTE: As far as AMotionEvent_getPointerId is concerned, keep in mind that while the id (e.g., slot) that it returns
--       is constant across a pointer's lifetime (i.e., a single gesture), its index *can* and *will* vary across events!
--       (As it's literally an index to the native MotionEvent array where the data is stored).
-- NOTE: The documentation is not always super clear on the fact that the data is always at index 0 for
--       AMOTION_EVENT_ACTION_DOWN & AMOTION_EVENT_ACTION_UP, so, use the source, Luke! c.f., TouchInputMapper::dispatchMotion @
-- https://android.googlesource.com/platform//frameworks/native/+/master/services/inputflinger/reader/mapper/TouchInputMapper.cpp
local function motionEventHandler(motion_event)
    if android.isTouchscreenIgnored() then
        return
    end

    local action = android.lib.AMotionEvent_getAction(motion_event)
    local flags = bit.band(action, C.AMOTION_EVENT_ACTION_MASK)
    if flags == C.AMOTION_EVENT_ACTION_DOWN then
        -- Happens on the *first* contact of a gesture (data is always at index 0),
        local slot = android.lib.AMotionEvent_getPointerId(motion_event, 0)
        setPointerDown(slot, true)
        genTouchDownEvent(motion_event, slot, 0)
    elseif flags == C.AMOTION_EVENT_ACTION_POINTER_DOWN then
        local pointer_index = bit.rshift(
                                        bit.band(action, C.AMOTION_EVENT_ACTION_POINTER_INDEX_MASK),
                                        C.AMOTION_EVENT_ACTION_POINTER_INDEX_SHIFT)
        local slot = android.lib.AMotionEvent_getPointerId(motion_event, pointer_index)
        setPointerDown(slot, true)
        genTouchDownEvent(motion_event, slot, pointer_index)
    elseif flags == C.AMOTION_EVENT_ACTION_UP then
        -- Happens once the *last* contact of a gesture has been lifted (data is always at index 0)
        local slot = android.lib.AMotionEvent_getPointerId(motion_event, 0)
        setPointerDown(slot, false)
        genTouchUpEvent(motion_event, slot, 0)
    elseif flags == C.AMOTION_EVENT_ACTION_POINTER_UP then
        local pointer_index = bit.rshift(
                                        bit.band(action, C.AMOTION_EVENT_ACTION_POINTER_INDEX_MASK),
                                        C.AMOTION_EVENT_ACTION_POINTER_INDEX_SHIFT)
        local slot = android.lib.AMotionEvent_getPointerId(motion_event, pointer_index)
        setPointerDown(slot, false)
        genTouchUpEvent(motion_event, slot, pointer_index)
    elseif flags == C.AMOTION_EVENT_ACTION_MOVE then
        -- There may be multiple pointers involved, only request the ts once
        local timev = genInputTimeval(android.lib.AMotionEvent_getEventTime(motion_event))

        -- This effectively gives us the size of the current MotionEvent array...
        local pointer_count = tonumber(android.lib.AMotionEvent_getPointerCount(motion_event))
        for i = 0, pointer_count - 1 do
            -- So, loop through the array, and if that pointer is still down, move it
            local slot = android.lib.AMotionEvent_getPointerId(motion_event, i)
            if pointers[slot] then
                genTouchMoveEvent(motion_event, timev, slot, i)
            end
        end

        -- Bundle everything in a single input frame
        genEndTouchEvent(motion_event, timev)
    elseif flags == C.AMOTION_EVENT_ACTION_CANCEL then
        -- Invalidate the pointers, and push a custom event to notify front to do the same.
        -- NOTE: We preserve the actual table object to avoid garbage churn,
        --       as we're liable to see a similar amount of slots show up again later.
        for slot, _ in pairs(pointers) do
            pointers[slot] = nil
        end
        genAndroidCancelEvent(motion_event)
    end
end

local function keyEventHandler(key_event)
    local code = android.lib.AKeyEvent_getKeyCode(key_event)
    local action = android.lib.AKeyEvent_getAction(key_event)
    if code == C.AKEYCODE_VOLUME_UP
    or code == C.AKEYCODE_VOLUME_DOWN then
        if android.getVolumeKeysIgnored() then
            return 0 -- event not consumed
        end
    elseif code == C.AKEYCODE_MEDIA_PLAY_PAUSE
    or code == C.AKEYCODE_MEDIA_PLAY
    or code == C.AKEYCODE_MEDIA_PAUSE
    or code == C.AKEYCODE_MEDIA_STOP
    or code == C.AKEYCODE_MEDIA_NEXT
    or code == C.AKEYCODE_MEDIA_PREVIOUS
    or code == C.AKEYCODE_MEDIA_REWIND
    or code == C.AKEYCODE_MEDIA_FAST_FORWARD then
        return 0 -- event not consumed
    elseif code == C.AKEYCODE_MUTE
    or code == C.AKEYCODE_VOLUME_MUTE then
        if android.getVolumeKeysIgnored() then
            return 0
        else
            return 1
        end
    end
    if code == C.AKEYCODE_BACK and android.isBackButtonIgnored() then
        return 1
    end
    if action == C.AKEY_EVENT_ACTION_DOWN then
        genEmuEvent(C.EV_KEY, code, 1, nil, android.lib.AKeyEvent_getEventTime(key_event))
    elseif action == C.AKEY_EVENT_ACTION_UP then
        genEmuEvent(C.EV_KEY, code, 0, nil, android.lib.AKeyEvent_getEventTime(key_event))
    end
    return 1 -- event consumed
end

local function commandHandler(code, value)
    genEmuEvent(C.EV_MSC, code, value)
end

function input.waitForEvent(sec, usec)
    -- TimeVal's :tomsecs if we were passed one to begin with, otherwise, -1 => block
    local timeout = sec and math.floor(sec * 1000000 + usec + 0.5) / 1000 or -1

    -- Reset the queue
    inputQueue = {}

    -- Will point to the the raw fd number
    local fd     = ffi.new("int[1]")
    -- Will point to the poll events
    local events = ffi.new("int[1]")
    -- Will point to the data passed at addFd/attachLooper time, c.f., the android_poll_source struct definition.
    -- NOTE: Its id field is mostly redundant, as ALooper already returns the ident.
    --       And its process function can be used as a weird delayed callback mechanism, but ALooper already has native callback handling :?.
    --       TL;DR: We don't actually use it here.
    local source = ffi.new("struct android_poll_source*[1]")
    -- NOTE: Much like the C backend, we only process a *single* fd per waitForEvent iteration.
    --       Although, in the Android case, things are a bit more complex, because this is a wrapper around epoll:
    --       the backend actually accumulates every poll event in a single (inner) iteration, and enqueues those in a list.
    --       That list is what the public function processes, and it processes it item by item, returning one item per call.
    --       c.f., https://android.googlesource.com/platform/system/core/+/refs/heads/master/libutils/Looper.cpp
    -- NOTE: We don't use callbacks, so pollOnce is good enough for us, no need to resort to pollAll :).
    local poll_state = android.lib.ALooper_pollOnce(timeout, fd, events, ffi.cast("void**", source))
    if poll_state >= 0 then
        -- NOTE: Since we actually want to process this in Lua-land (i.e., here), and not in C-land,
        --       we do *NOT* make use of the weird delayed callback mechanism afforded by the android_poll_source struct
        --       we pass as the data pointer to ALooper in the glue code when registering a polling source.
        --       Instead, we do everything here, which is why this may look eerily like the C functions
        --       process_cmd & process_input in the glue code.
        --       Sidebar: if you *actually* need to process stuff in C-land ASAP, use ALooper's native callback system.
        if poll_state == C.LOOPER_ID_MAIN then
            -- e.g., source[0].process(android.app, source[0]) where process would point to process_cmd
            local cmd = android.glue.android_app_read_cmd(android.app)
            while cmd ~= -1 do
                android.glue.android_app_pre_exec_cmd(android.app, cmd)
                commandHandler(cmd, 1)
                android.glue.android_app_post_exec_cmd(android.app, cmd)

                -- Should return -1 (EAGAIN) when we've drained the pipe
                cmd = android.glue.android_app_read_cmd(android.app)
            end
        elseif poll_state == C.LOOPER_ID_INPUT then
            -- e.g., source[0].process(android.app, source[0]) where process would point to process_input
            local event = ffi.new("AInputEvent*[1]")
            while android.lib.AInputQueue_getEvent(android.app.inputQueue, event) >= 0 do
                if android.lib.AInputQueue_preDispatchEvent(android.app.inputQueue, event[0]) == 0 then
                    local event_type = android.lib.AInputEvent_getType(event[0])
                    local handled = 1
                    if event_type == C.AINPUT_EVENT_TYPE_MOTION then
                        motionEventHandler(event[0])
                    elseif event_type == C.AINPUT_EVENT_TYPE_KEY then
                        handled = keyEventHandler(event[0])
                    end
                    android.lib.AInputQueue_finishEvent(android.app.inputQueue, event[0], handled)
                end
            end
        elseif poll_state == C.LOOPER_ID_USER then
            local message = ffi.new("unsigned char [4]")
            -- Similarly, read will return -1 (EAGAIN) when we've drained the pipe
            while C.read(fd[0], message, 4) == 4 do
                if message[0] == C.AEVENT_POWER_CONNECTED then
                    commandHandler(C.AEVENT_POWER_CONNECTED, 0)
                elseif message[0] == C.AEVENT_POWER_DISCONNECTED then
                    commandHandler(C.AEVENT_POWER_DISCONNECTED, 0)
                elseif message[0] == C.AEVENT_DOWNLOAD_COMPLETE then
                    commandHandler(C.AEVENT_DOWNLOAD_COMPLETE, 0)
                end
            end
        end
        if android.app.destroyRequested ~= 0 then
            android.LOGI("Engine thread destroy requested!")
            -- Do nothing, if this is set, we've already pushed an APP_CMD_DESTROY event that'll get handled in front.
        end
    elseif poll_state == C.ALOOPER_POLL_TIMEOUT then
        return false, C.ETIME
    elseif poll_state == C.ALOOPER_POLL_ERROR then
        android.LOGE("Encountered a polling error!")
        return
    end
    -- NOTE: We never set callbacks, and we never call wake, so no need to check for ALOOPER_POLL_CALLBACK & ALOOPER_POLL_WAKE

    if #inputQueue > 0 then
        -- We generated some actionable events
        return true, inputQueue
    else
        -- poll returned early, but without an event we actually use.
        -- Back to Input:waitEvent to recompute the timeout
        return false, C.EINTR
    end
end

function input.fakeTapInput() end
function input.closeAll() end

return input
