--[[--
Module for interfacing with the RTC (real time clock).

This module provides the ability to schedule wakeups through RTC.

See <http://man7.org/linux/man-pages/man4/rtc.4.html> for technical details.

Things to keep in mind: the RTC tracks time in UTC.
So do we, as the API only passes around what amounts to time_t values,
i.e., a Posix epoch, which is intrinsically UTC.

@module ffi.rtc
]]

local ffi = require("ffi")
local bor = bit.bor
local C = ffi.C

-- Load header definitions for functions and constants to the ffi.C namespace.
require("ffi/posix_h")
require("ffi/rtc_h")

-----------------------------------------------------------------

local RTC = {
    dev_rtc = "/dev/rtc0",
    dodgy_rtc = false,
    _wakeup_scheduled = false,  -- Flipped in @{setWakeupAlarm} and @{unsetWakeupAlarm}.
    _wakeup_scheduled_tm = nil, -- The tm struct of the last scheduled wakeup alarm.
}

--[[--
Adds seconds to epoch.

@int seconds_from_now Number of seconds.
@treturn int (cdata) Epoch (UTC).
--]]
function RTC:secondsFromNowToEpoch(seconds_from_now)
    -- NOTE: Lua's os.time just calls time(), which returns an epoch (UTC).
    return os.time() + seconds_from_now
end


--[[--
Enable/Disable the alarm interrupt.
The use of RTC_WKALM_SET allows us to bypass the need for RTC_AIE_* calls,
thanks to the enabled field in the rtc_wkalrm struct.
Busybox rtcwake still does an RTC_AIE_OFF when resuming from an alarm wakeup,
as does Nickel when powering off.
In this scenario, the modern util-linux rtcwake, which never uses legacy RTC_ALM_SET calls,
instead uses RTC_WKALM_SET filled from RTC_WKALM_RD but with enabled set to 0.

@enabled bool Whether the call enables or disables the alarm interrupt. Defaults to true.

@treturn bool Success.
@treturn re Error code (if any).
@treturn err Error string (if any).
--]]
function RTC:toggleAlarmInterrupt(enabled)
    enabled = (enabled ~= nil) and enabled or true

    local err
    local fd = C.open(self.dev_rtc, bor(C.O_RDONLY, C.O_NONBLOCK, C.O_CLOEXEC))
    if fd == -1 then
        err = ffi.string(C.strerror(ffi.errno()))
        print("toggleAlarmInterrupt open " .. self.dev_rtc, fd, err)
        return nil, fd, err
    end
    local re = C.ioctl(fd, enabled and C.RTC_AIE_ON or C.RTC_AIE_OFF, 0)
    if re == -1 then
        err = ffi.string(C.strerror(ffi.errno()))
        if enabled then
            print("toggleAlarmInterrupt ioctl RTC_AIE_ON", re, err)
        else
            print("toggleAlarmInterrupt ioctl RTC_AIE_OFF", re, err)
        end
        return nil, re, err
    end
    re = C.close(fd)
    if re == -1 then
        err = ffi.string(C.strerror(ffi.errno()))
        print("toggleAlarmInterrupt close " .. self.dev_rtc, re, err)
        return nil, re, err
    end

    return true
end

--[[--
Set wakeup alarm.

If you want to set the alarm to a certain amount of time from now,
you can process your value with @{secondsFromNowToEpoch}.

@int Epoch (UTC).
@enabled bool Whether the call enables or disables the alarm. Defaults to true.

@treturn bool Success.
@treturn re Error code (if any).
@treturn err Error string (if any).
--]]
function RTC:setWakeupAlarm(epoch, enabled)
    enabled = (enabled ~= nil) and enabled or true

    self._wakeup_scheduled_tm = ffi.new("struct tm")
    local ptm = C.gmtime_r(ffi.new("time_t[1]", epoch), self._wakeup_scheduled_tm)

    local wake = ffi.new("struct rtc_wkalrm")
    wake.time.tm_sec = ptm.tm_sec
    wake.time.tm_min = ptm.tm_min
    wake.time.tm_hour = ptm.tm_hour
    wake.time.tm_mday = ptm.tm_mday
    wake.time.tm_mon = ptm.tm_mon
    wake.time.tm_year = ptm.tm_year
    -- wday, yday, and isdst fields are unused by Linux
    wake.time.tm_wday = -1
    wake.time.tm_yday = -1
    wake.time.tm_isdst = -1

    wake.enabled = enabled and 1 or 0

    local err
    local fd = C.open(self.dev_rtc, bor(C.O_RDONLY, C.O_NONBLOCK, C.O_CLOEXEC))
    if fd == -1 then
        err = ffi.string(C.strerror(ffi.errno()))
        print("setWakeupAlarm open " .. self.dev_rtc, fd, err)
        return nil, fd, err
    end
    local re = C.ioctl(fd, C.RTC_WKALM_SET, wake)
    if re == -1 then
        err = ffi.string(C.strerror(ffi.errno()))
        print("setWakeupAlarm ioctl RTC_WKALM_SET", re, err)
        return nil, re, err
    end
    re = C.close(fd)
    if re == -1 then
        err = ffi.string(C.strerror(ffi.errno()))
        print("setWakeupAlarm close " .. self.dev_rtc, re, err)
        return nil, re, err
    end

    if enabled then
        self._wakeup_scheduled = true
    else
        self._wakeup_scheduled = false
        self._wakeup_scheduled_ptm = nil
    end
    return true
end

--[[--
Unset wakeup alarm.
--]]
function RTC:unsetWakeupAlarm()
    -- NOTE: Both util-linux & busybox rtcwake leave the current alarm as-is, and just disable the alarm interrupt.
    --       c.f., toggleAlarmInterrupt for details.
    self:toggleAlarmInterrupt(false)
    self._wakeup_scheduled = false
    self._wakeup_scheduled_tm = nil
end

--[[--
Get a copy of the wakealarm we set (if any).

This value is compared with @{getWakeupAlarmSys} in @{validateWakeupAlarmByProximity}.

@treturn tm (time struct)
--]]
function RTC:getWakeupAlarm()
    return self._wakeup_scheduled_tm
end

--[[--
Return the timestamp of the alarm we set (if any).

@treturn @int Epoch (UTC)
--]]
function RTC:getWakeupAlarmEpoch()
    if self._wakeup_scheduled then
        return tonumber(C.timegm(self._wakeup_scheduled_tm))
    else
        return nil
    end
end

--[[--
Get RTC wakealarm from system.

@treturn tm (time struct)
--]]
function RTC:getWakeupAlarmSys()
    local wake = ffi.new("struct rtc_wkalrm")

    local err, re
    local fd = C.open(self.dev_rtc, bor(C.O_RDONLY, C.O_NONBLOCK, C.O_CLOEXEC))
    if fd == -1 then
        err = ffi.string(C.strerror(ffi.errno()))
        print("getWakeupAlarm open " .. self.dev_rtc, fd, err)
        return nil, fd, err
    end
    re = C.ioctl(fd, C.RTC_WKALM_RD, wake)
    if re == -1 then
        err = ffi.string(C.strerror(ffi.errno()))
        print("getWakeupAlarm ioctl RTC_WKALM_RD", re, err)
        return nil, re, err
    end
    re = C.close(fd)
    if re == -1 then
        err = ffi.string(C.strerror(ffi.errno()))
        print("getWakeupAlarm close " .. self.dev_rtc, re, err)
        return nil, re, err
    end

    -- Seed a struct tm with the current time, because not every field will be set in wake
    local t = ffi.new("time_t[1]")
    t[0] = C.time(nil)
    local tm = ffi.new("struct tm")
    local ptm = C.gmtime_r(t, tm)
    -- And now update it with the fields that *are* set by the ioctl
    ptm.tm_sec = wake.time.tm_sec
    ptm.tm_min = wake.time.tm_min
    ptm.tm_hour = wake.time.tm_hour
    ptm.tm_mday = wake.time.tm_mday
    ptm.tm_mon = wake.time.tm_mon
    ptm.tm_year = wake.time.tm_year
    return tm
end

--[[--
Get RTC clock from system.

@treturn tm (time struct)
--]]
function RTC:readHardwareClock()
    local rtc = ffi.new("struct rtc_time")

    local err, re
    local fd = C.open(self.dev_rtc, bor(C.O_RDONLY, C.O_NONBLOCK, C.O_CLOEXEC))
    if fd == -1 then
        err = ffi.string(C.strerror(ffi.errno()))
        print("readHardwareClock open " .. self.dev_rtc, fd, err)
        return nil, fd, err
    end
    re = C.ioctl(fd, C.RTC_RD_TIME, rtc)
    if re == -1 then
        err = ffi.string(C.strerror(ffi.errno()))
        print("readHardwareClock ioctl RTC_RD_TIME", re, err)
        return nil, re, err
    end
    re = C.close(fd)
    if re == -1 then
        err = ffi.string(C.strerror(ffi.errno()))
        print("readHardwareClock close " .. self.dev_rtc, re, err)
        return nil, re, err
    end

    -- Seed a struct tm with the current time, because not every field will be set in rtc
    local t = ffi.new("time_t[1]")
    t[0] = C.time(nil)
    local tm = ffi.new("struct tm")
    local ptm = C.gmtime_r(t, tm)
    -- And now update it with the fields that *are* set by the ioctl
    ptm.tm_sec = rtc.tm_sec
    ptm.tm_min = rtc.tm_min
    ptm.tm_hour = rtc.tm_hour
    ptm.tm_mday = rtc.tm_mday
    ptm.tm_mon = rtc.tm_mon
    ptm.tm_year = rtc.tm_year
    return tm
end

--[[--
Checks if the alarm we set matches the system alarm as well as the current time.
--]]
function RTC:validateWakeupAlarmByProximity(task_alarm, proximity)
    -- In principle alarm time and current time should match within a second,
    -- but let's be absurdly generous and assume anything within 30 is a match.
    -- In practice, Kobo's suspend() schedules check_unexpected_wakeup 15s *after*
    -- the actual wakeup, so we need to account for at least that much ;).
    proximity = proximity or 30

    -- Those are in UTC broken down time format (struct tm)
    local alarm_tm = self:getWakeupAlarm()
    local alarm_sys_tm = self:getWakeupAlarmSys()

    if not (alarm_tm and alarm_sys_tm) then return end

    -- We want everything in UTC time_t (i.e. a Posix epoch).
    local now = os.time()
    local rtc_now_tm = self:readHardwareClock()
    -- time_t may be 64-bit, cast to a Lua number
    local rtc_now = tonumber(C.timegm(rtc_now_tm))
    local alarm = tonumber(C.timegm(alarm_tm))
    local alarm_sys = tonumber(C.timegm(alarm_sys_tm))

    -- Everything's in UTC, ask Lua to convert that to a human-readable format in the local timezone
    -- NOTE: Ideally, the first three entries should be identical.
    if task_alarm then
        print("validateWakeupAlarmByProximity:",
            "\ntask              @ " .. task_alarm .. os.date(" (%F %T %z)", task_alarm), -- what we were asked to validate
            "\nlast set alarm    @ " .. alarm .. os.date(" (%F %T %z)", alarm),           -- the last alarm *we* setup
            "\ncurrent rtc alarm @ " .. alarm_sys .. os.date(" (%F %T %z)", alarm_sys),   -- the current rtc alarm
            "\ncurrent rtc time is " .. rtc_now .. os.date(" (%F %T %z)", rtc_now),
            "\ncurrent time is     " .. now .. os.date(" (%F %T %z)", now))
    end

    -- On dodgy RTCs, some aging batteries are (supposedly) causing reads to report a bogus value...
    -- c.f., https://github.com/koreader/koreader/issues/7994 & https://github.com/koreader/koreader/issues/10996
    if self.dodgy_rtc and alarm_sys <= 1 then
        print("A dodgy RTC reported a bogus alarm value, assuming our previously set alarm fired as expected anyway")
        alarm_sys = alarm
    end

    -- If our stored alarm and the system alarm don't match, we didn't set it.
    if alarm ~= alarm_sys then return end

    -- If our stored alarm and the provided task alarm don't match,
    -- we're not talking about the same task. This should never happen.
    if task_alarm and alarm ~= task_alarm then return end

    local diff = now - alarm
    if diff >= 0 and diff < proximity then return true end
end

--[[--
Checks if we scheduled a wakeup alarm.

@treturn bool
--]]
function RTC:isWakeupAlarmScheduled()
    return self._wakeup_scheduled
end

-- Helpers for HCToSys
local function set_kernel_tz(tz)
    local re = C.settimeofday(nil, tz)
    if re == -1 then
        local err = ffi.string(C.strerror(ffi.errno()))
        print("set_kernel_tz settimeofday", re, err)
        return nil, re, err
    end

    return true
end

--[[--
Sets the system clock based on the hardware clock.

(e.g., hwclock --hctosys).
Heavily inspired by busybox's hwclock applet.
--]]
function RTC:HCToSys()
    local ok, err, re
    local fd = C.open(self.dev_rtc, bor(C.O_RDONLY, C.O_NONBLOCK, C.O_CLOEXEC))
    if fd == -1 then
        err = ffi.string(C.strerror(ffi.errno()))
        print("HCToSys open " .. self.dev_rtc, fd, err)
        return nil, fd, err
    end

    -- Read the hardware clock
    local tm = ffi.new("struct tm") -- tm is a superset of rtc_time, so we're good.
    re = C.ioctl(fd, C.RTC_RD_TIME, tm)
    if re == -1 then
        err = ffi.string(C.strerror(ffi.errno()))
        print("HCToSys ioctl RTC_RD_TIME", re, err)
        return nil, re, err
    end
    re = C.close(fd)
    if re == -1 then
        err = ffi.string(C.strerror(ffi.errno()))
        print("HCToSys close ".. self.dev_rtc, re, err)
        return nil, re, err
    end

    -- Convert that UTC broken down representation to an UTC time_t...
    local t = C.timegm(tm)

    -- We want a timeval for settimeofday
    local tv = ffi.new("struct timeval")
    tv.tv_sec = t

    -- Deal with some more kernel & TZ nonsense...
    -- 1. Lock the kernel's warp_clock function
    --    (iff that's the first settimeofday call after a cold boot! i.e., in our case, that's mostly going to be a NOP).
    -- 2. Set the kernel timezone.
    -- c.f., comments in hwclock in both busybox & util-linux, as well as gettimeofday(2) for more details.
    local tz = ffi.new("struct timezone")
    ok, re, err = set_kernel_tz(tz)
    if not ok then
        return nil, re, err
    end
    local cur = ffi.new("time_t[1]")
    cur[0] = C.time(nil)
    local broken = C.localtime(cur)
    tz.tz_minuteswest = -broken.tm_gmtoff / 60
    ok, re, err = set_kernel_tz(tz)
    if not ok then
        return nil, re, err
    end

    -- Finally set the system clock
    re = C.settimeofday(tv, nil)
    if re == -1 then
        err = ffi.string(C.strerror(ffi.errno()))
        print("HCToSys settimeofday", re, err)
        return nil, re, err
    end

    return true
end

return RTC
