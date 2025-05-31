--- Turbo.lua I/O Loop module
-- Single threaded I/O event loop implementation. The module handles socket
-- events and timeouts and scheduled intervals with millisecond precision.
--
-- Supports the following implementations:
-- * epoll
-- The IOLoop class is written in such a way that adding new poll
-- implementations is easy.
--
-- Copyright 2011, 2012, 2013 John Abrahamsen
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local log = require "turbo.log"
local util = require "turbo.util"
local signal = require "turbo.signal"
local socket = require "turbo.socket_ffi"
local coctx = require "turbo.coctx"
local platform = require "turbo.platform"
local ffi = require "ffi"
local bit = jit and require "bit" or require "bit32"
require "turbo.3rdparty.middleclass"

local unpack = util.funpack
local ioloop = {} -- ioloop namespace

local epoll_ffi, _poll_implementation
-- Backtrace formatters.
local _str_borders_down = string.rep("▼", 80)
local _str_borders_up = string.rep("▲", 80)

if platform.__LINUX__ and not _G.__TURBO_USE_LUASOCKET__ then
    -- Epoll FFI module found and loaded.
    _poll_implementation = "epoll_ffi"
    epoll_ffi = require "turbo.epoll_ffi"
    ioloop.READ = epoll_ffi.EPOLL_EVENTS.EPOLLIN
    ioloop.WRITE = epoll_ffi.EPOLL_EVENTS.EPOLLOUT
    ioloop.PRI = epoll_ffi.EPOLL_EVENTS.EPOLLPRI
    ioloop.ERROR = bit.bor(epoll_ffi.EPOLL_EVENTS.EPOLLERR,
        epoll_ffi.EPOLL_EVENTS.EPOLLHUP)
elseif _G.__TURBO_USE_LUASOCKET__ then
    -- Load luasocket as a option.
    luasocket = require "socket"
    _poll_implementation = "luasocket"
    ioloop.READ = 0x001
    ioloop.WRITE = 0x004
    ioloop.ERROR = bit.bor(0x008, 0x0010)
end

--- Create or get the global IOLoop instance.
-- Multiple calls to this function returns the same IOLoop.
-- @return IOLoop class instance.
function ioloop.instance(func)
    local iol
    if _G.io_loop_instance then
        iol =  _G.io_loop_instance
    else
        iol = ioloop.IOLoop()
        _G.io_loop_instance = iol 
    end
    if func then
        iol:add_callback(func, iol)
    end
    return iol
end

--- IOLoop is a level triggered I/O loop, with additional support for timeout
-- and time interval callbacks.
-- Heavily influenced by ioloop.py in the Tornado web framework.
-- @note Only one instance of IOLoop can ever run at the same time!
ioloop.IOLoop = class('IOLoop')

--- Create a new IOLoop class instance.
function ioloop.IOLoop:initialize()
    self._co_cbs = {}
    self._co_ctxs = {}
    self._handlers = {}
    self._timeouts = {}
    self._intervals = {}
    self._callbacks = {}
    self._signalfds = {}
    self._timeouts_sz = 0
    self._intervals_sz = 0
    self._running = false
    self._stopped = false
    -- Set the most fitting poll implementation. The API's are all unified.
    if _poll_implementation == "epoll_ffi" then
        self._poll = _EPoll_FFI()
        signal.signal(signal.SIGPIPE, signal.SIG_IGN)
    elseif _poll_implementation == "luasocket" then
        self._poll = _LuaSocketPoll()
        -- do nothing
    end
end

--- Add handler function for given event mask on fd.
-- @param fd (Number) File descriptor to bind handler for.
-- @param events (Number) Events bit mask. Defined in ioloop namespace. E.g
-- ioloop.READ and ioloop.WRITE. Multiple bits can be AND'ed together.
-- @param handler (Function) Handler function.
-- @param arg Optional argument for function handler. Handler is called with
-- this as first argument if set.
-- @return (Boolean) true if successfull else false.
function ioloop.IOLoop:add_handler(fd, events, handler, arg)
    local rc, errno = self._poll:register(fd, bit.bor(events, ioloop.ERROR))
    if rc ~= 0 then
        log.notice(
            string.format(
                "[ioloop.lua] register() in add_handler() failed: %s",
                socket.strerror(errno)))
        return false
    end
    self._handlers[fd] = {handler, arg}
    return true
end

--- Update existing handler function's trigger events.
-- @param fd (Number) File descriptor to update events for.
-- @param events (Number) Events bit mask. Defined in ioloop namespace. E.g
-- ioloop.READ and ioloop.WRITE. Multiple bits can be AND'ed together.
-- @return (Boolean) true if successfull else false.
function ioloop.IOLoop:update_handler(fd, events)
    local rc, errno = self._poll:modify(fd, bit.bor(events, ioloop.ERROR))
    if rc ~= 0 then
        log.notice(
            string.format(
                "[ioloop.lua] modify() in update_handler() failed: %s",
                socket.strerror(errno)))
        return false
    end
    return true
end

--- Remove a existing handler from the IO Loop.
-- @param fd (Number) File descriptor to remove handler from.
-- @return (Boolean) true if successfull else false.
function ioloop.IOLoop:remove_handler(fd)
    if not self._handlers[fd] then
        return
    end
    local rc, errno = self._poll:unregister(fd)
    if rc ~= 0 then
        log.notice(
            string.format(
                "[ioloop.lua] unregister() in remove_handler() failed: %s",
                socket.strerror(errno)))
        return false
    end
    self._handlers[fd] = nil
    return true
end

--- Check if IOLoop is currently in a running state.
-- @return (Boolean) true or false.
function ioloop.IOLoop:running() return self._running end

--- Add a callback to be run on next iteration of the IOLoop.
-- @param callback (Function)
-- @param arg Optional argument to call callback with as first argument.
-- @return (IOLoop class) Return self for convinience.
function ioloop.IOLoop:add_callback(callback, arg)
    self._callbacks[#self._callbacks + 1] = {callback, arg}
    return self
end

--- Finalize a coroutine context.
-- @param coctx A CourtineContext instance.
-- @return True if suscessfull else false.
function ioloop.IOLoop:finalize_coroutine_context(coctx)
    local coroutine = self._co_ctxs[coctx]
    if not coroutine then
        log.warning("[ioloop.lua] Trying to finalize a coroutine context \
            that there are no reference to.")
        return false
    end
    self._co_ctxs[coctx] = nil
    self:_resume_coroutine(coroutine, coctx:get_coroutine_arguments())
    return true
end

--- Add a timeout with function to be called in future.
-- @param timestamp (Number) Timestamp when to call function. Based on
-- Unix CLOCK_MONOTONIC time in milliseconds precision.
-- E.g util.gettimemonotonic + 3000 will timeout in 3 seconds.
-- @param func (Function)
-- @param Optional argument for func.
-- @return (Number) Reference to timeout.
function ioloop.IOLoop:add_timeout(timestamp, func, arg) 
    local i = 1

    while self._timeouts[i] ~= nil do
        -- Find hole in Lua table...
        i = i + 1
    end
    self._timeouts_sz = self._timeouts_sz + 1
    self._timeouts[i] = _Timeout(timestamp, func, arg)
    return i
end

--- Remove timeout.
-- @param ref (Number) The reference returned by IOLoop:add_timeout.
-- @return (Boolean) True on success, else false.
function ioloop.IOLoop:remove_timeout(ref)
    if self._timeouts[ref] then
        self._timeouts[ref] = nil
        self._timeouts_sz = self._timeouts_sz - 1
        return true
    else
        return false
    end
end

--- Set function to be called on given interval.
-- @param msec (Number) Call func every msec.
-- @param func (Function)
-- @param Optional argument for func.
-- @return (Number) Reference to interval.
function ioloop.IOLoop:set_interval(msec, func, arg)
    local i = 1

    while self._intervals[i] ~= nil do
        -- Find hole in Lua table...
        i = i + 1
    end
    self._intervals[i] = _Interval(msec, func, arg)
    self._intervals_sz = self._intervals_sz + 1
    return i
end

--- Clear interval.
-- @param ref (Number) The reference returned by IOLoop:set_interval.
-- @return (Boolean) True on success, else false.
function ioloop.IOLoop:clear_interval(ref)
    if self._intervals[ref] then
        self._intervals[ref] = nil
        self._intervals_sz = self._intervals_sz - 1
        return true
    else
        return false
    end
end

-- Handle event on a signalfd.
function ioloop.IOLoop:_handle_signalfd_event(fd, events)
    local sigfdsi = ffi.new("struct signalfd_siginfo[1]")
    local sigfdsi_size = ffi.sizeof("struct signalfd_siginfo")
    ffi.fill(sigfdsi, sigfdsi_size)
    local r = ffi.C.read(fd, sigfdsi, sigfdsi_size)
    if r ~= sigfdsi_size then
        log.notice(string.format(
            "[ioloop.lua] read() in _handle_signalfd_event failed: %s",
            socket.strerror(ffi.errno())))
        return
    end
    local fdsi = sigfdsi[0]
    local siginfo = {
        signo=fdsi.ssi_signo,       -- Signal number
        errno=fdsi.ssi_errno,       -- Error number (currently unused)
        code=fdsi.ssi_code,         -- Signal code
        pid=fdsi.ssi_pid,           -- pid of sender
        uid=fdsi.ssi_uid,           -- uid of sender
        fd=fdsi.ssi_fd,             -- File descriptor (SIGIO)
        tid=fdsi.ssi_tid,           -- Kernel timer ID (POSIX timers)
        band=fdsi.ssi_band,         -- Band event (SIGIO)
        overrun=fdsi.ssi_overrun,   -- POSIX time overrun count
        trapno=fdsi.ssi_trapno,     -- Trap number that caused signal
        status=fdsi.ssi_status,     -- Exit status or signal (SIGCHLD)
        int=fdsi.ssi_int,           -- Integer sent by sigqueue(3)
        ptr=fdsi.ssi_ptr,           -- Pointer sent by sigqueue(3)
        utime=fdsi.ssi_utime,       -- User CPU time consumed (SIGCHLD)
        stime=fdsi.ssi_stime,       -- System CPU time consumed (SIGCHLD)
        addr=fdsi.ssi_addr          -- Address that generated signal
                                    -- (for hardware signals)
    }
    local signo, handler, arg = unpack(self._signalfds[fd])
    if arg then
        handler(arg, siginfo.signo, siginfo, fd)
    else
        handler(siginfo.signo, siginfo, fd)
    end
end

--- Add signal handler.
-- @param signos (Number) the signal number(s) to handle
-- @param handler (Function) Handler function.
-- @param arg Optional argument for handler. Handler is called with
--            this as first argument if set.
function ioloop.IOLoop:add_signal_handler(signo, handler, arg)
    assert(signo ~= signal.SIGPIPE,
        "Cannot add handler for SIGPIPE. Reserved by IOLoop.")
    local mask = ffi.new("sigset_t[1]")
    ffi.C.sigemptyset(mask)
    ffi.C.sigaddset(mask, signo)
    ffi.C.sigprocmask(signal.SIG_BLOCK, mask, nil)
    local sfd = ffi.C.signalfd(-1, mask, 0)
    if sfd == -1 then
        log.notice(string.format(
            "[ioloop.lua] signalfd() in add_signal_handler() failed: %s",
            socket.strerror(ffi.errno())))
        return false
    end
    local r = self:add_handler(sfd, ioloop.READ,
                               self._handle_signalfd_event, self)
    if not r then
        log.notice("[ioloop.lua] add_handler() in add_signal_handler() failed.")
        return false
    end
    self:remove_signal_handler(signo) -- remove in case we already have one.
    self._signalfds[sfd] = {signo, handler, arg}
end

--- Remove signal handler.
-- @param signo (Number) the signal number to remove handler for.
function ioloop.IOLoop:remove_signal_handler(signo)
    for k, v in pairs(self._signalfds) do
        if v then
            if v[1] == signo then
                self._signalfds[k] = nil
                self:remove_handler(k)
                return
            end
        end
    end
end

--- Start the I/O Loop.
-- The loop will continue running until IOLoop.close is called via a callback
-- added.
function ioloop.IOLoop:start()
    self._running = true
    while true do
        local poll_timeout = 3600
        local co_cbs_sz = #self._co_cbs
        if co_cbs_sz > 0 then
            local co_cbs = self._co_cbs
            self._co_cbs = {}
            for i = 1, co_cbs_sz do
                if co_cbs[i] ~= nil then
                    -- co_cbs[i][1] = coroutine (Lua thread).
                    -- co_cbs[i][2] = yielded function.
                    if self:_resume_coroutine(
                        co_cbs[i][1],
                        co_cbs[i][2]) ~= 0 then
                        -- Resumed courotine yielded. Adjust timeout.
                        poll_timeout = 0
                    end
                end
            end
        end
        local callbacks = self._callbacks
        self._callbacks = {}
        for i = 1, #callbacks, 1 do
            if self:_run_callback(callbacks[i]) ~= 0 then
                -- Function yielded and has been scheduled for next iteration.
                -- Drop timeout.
                poll_timeout = 0
            end
        end
        local timeout_sz = self._timeouts_sz
        if timeout_sz ~= 0 then
            local current_time = util.gettimemonotonic()
            local timeouts_run = 0
            local i = 0
            while timeouts_run ~= timeout_sz do
                if self._timeouts[i] ~= nil then
                    timeouts_run = timeouts_run + 1
                    local time_until_timeout = 
                        self._timeouts[i]:timed_out(current_time)
                    if time_until_timeout == 0 then
                        self:_run_callback({self._timeouts[i]:callback()})
                        self._timeouts[i] = nil
                        self._timeouts_sz = self._timeouts_sz - 1
                        -- Function may have scheduled work for next iteration
                        -- must Drop timeout, without this, yielding from a request
                        -- handler that adds a timeout couroutine task will not wake
                        -- up the request handler at the end of the timeout until the
                        -- next poll_timeout occurs which may be as long as the default
                        -- timeout of 3.6 seconds.
                        poll_timeout = 0
                    else
                        if poll_timeout > time_until_timeout then
                           poll_timeout = time_until_timeout
                        end
                    end
                end
                i = i + 1
            end
        end
        local intervals_sz = self._intervals_sz
        if intervals_sz ~= 0 then
            local time_now = util.gettimemonotonic()
            local intervals_run = 0
            local i = 0
            while intervals_run ~= intervals_sz do
                local interval = self._intervals[i]
                if interval ~= nil then
                    intervals_run = intervals_run + 1
                    local timed_out = interval:timed_out(time_now)
                    if timed_out == 0 then
                        self:_run_callback({
                            interval.callback,
                            interval.arg
                            })
                        -- Get current time to protect against building
                        -- diminishing interval time on heavy functions.
                        -- It is debatable wether this feature is wanted or not.
                        time_now = util.gettimemonotonic()
                        local next_call = interval:set_last_call(
                            time_now)
                        if next_call < poll_timeout then
                            poll_timeout = next_call
                        end
                    else
                        if timed_out < poll_timeout then
                            -- Adjust timeout to not miss time out.
                            poll_timeout = timed_out
                        end
                    end
                end
                i = i + 1
            end
        end
        if self._stopped == true then
            self._running = false
            self._stopped = false
            break
        end
        if #self._callbacks > 0 then
            -- New callback has been scheduled for next iteration. Drop
            -- timeout.
            poll_timeout = 0
        end
        self:_event_poll(poll_timeout)
    end
end

if _poll_implementation == "epoll_ffi" then
    -- Linux version.
    function ioloop.IOLoop:_event_poll(poll_timeout)
        local rc, num, events = self._poll:poll(poll_timeout)
        if rc == 0  then
            num = num - 1 -- Base 0 loop
            for i = 0, num do
                self:_run_handler(events[i].data.fd, events[i].events)
            end
        elseif rc == -1 then
            log.notice(string.format("[ioloop.lua] poll() returned errno %d",
                ffi.errno()))
        end
    end
elseif _poll_implementation == "luasocket" then
    -- Everyone else version, based on LuaSocket which everyone has.
    function ioloop.IOLoop:_event_poll(poll_timeout)
        local recvt, sendt, err = self._poll:poll(poll_timeout/1000)
        if err and err ~= "timeout" then
            log.error("[ioloop.lua] LuaSocket select() returned: " .. err)
        end
        for _, r in ipairs(recvt) do
            local handler_run = false
            for i=1, #sendt, 1 do
                -- Run through send table too so that we combine multiple
                -- events into instead of running handler multiple times.
                s = sendt[i]
                if s == r then
                    handler_run = true
                    self:_run_handler(r, bit.band(ioloop.READ, ioloop.WRITE))
                    table.remove(sendt, i)
                    break
                end
            end
            self:_run_handler(r, ioloop.READ)
        end
        for _, v in ipairs(sendt) do
            self:_run_handler(v, ioloop.WRITE)
        end
    end
end

--- Close the I/O loop.
-- This call must be made from within the running I/O loop via a
-- callback, timeout, or interval. Notice: All pending callbacks and handlers
-- are cleared upon close.
function ioloop.IOLoop:close()
    self._running = false
    self._stopped = true
end

--- Run IOLoop for specified amount of time. Used in Turbo.lua tests.
-- @param timeout In seconds.
function ioloop.IOLoop:wait(timeout)
    assert(self:running() == false, "Can not wait, already started")
    local timedout
    local ref
    if timeout then
        local _ioloop = self
        ref = self:add_timeout(util.gettimemonotonic() + (timeout*1000), function()
            timedout = true
            _ioloop:close()
        end)
    end
    self:start()
    assert(self:running() == false, "IO Loop stopped unexpectedly")
    assert(not timedout, "Sync wait operation timed out.")
    self:remove_timeout(ref)
    return true
end

--- Error handler for IOLoop:_run_handler.
local function _run_handler_error_handler(err)
    log.error(
        string.format(
            "[ioloop.lua] Error in IOLoop handler.\n%s\n%s\n%s",
            _str_borders_down,
            debug.traceback(err, 2),
            _str_borders_up))
end

--- Run callbacks protected with error handlers. Because errors can always
-- happen! If a handler errors, the handler is removed from the IOLoop, and
-- never called again.
function ioloop.IOLoop:_run_handler(fd, events)
    local ok
    local handler = self._handlers[fd]
    if not handler then
        log.error(string.format("Critical error, no handler for fd: %d.", fd))
        return
    end
    -- handler[1] = function.
    -- handler[2] = optional first argument for function.
    -- If there is no optional argument, do not add it as parameter to the
    -- function as that creates a big nuisance for consumers of the API.
    local func = handler[1]
    local arg = handler[2]

    if arg then
        ok = xpcall(
            func,
            _run_handler_error_handler,
            arg,
            fd,
            events)
    else
        ok = xpcall(
            func,
            _run_handler_error_handler,
            fd,
            events)
    end
    if ok == false then
        -- Error in handler caught by _run_handler_error_handler.
        -- Remove the handler for the fd as its most likely broken.
        self:remove_handler(fd)
    end
end

local function _run_callback_error_handler(err)
    local thread = coroutine.running()
    log.error(
        string.format(
            "[ioloop.lua] Error in IOLoop callback, %s is dead.\n%s\n%s\n%s",
            thread,
            _str_borders_down,
            debug.traceback(coroutine.running(), err, 2),
            _str_borders_up))
end

local function _run_callback_protected(func, arg)
    xpcall(func, _run_callback_error_handler, arg)
end

function ioloop.IOLoop:_run_callback(callback)
    local co = coroutine.create(_run_callback_protected)
    -- callback index 1 = function
    -- callback index 2 = arg
    local func = callback[1]
    local arg = callback[2]

    local rc = self:_resume_coroutine(co, {func, arg})
    return rc
end

function ioloop.IOLoop:_resume_coroutine(co, arg)
    local err, yielded, st
    local arg_t = type(arg)
    if arg_t == "function" then
        -- Function as argument. Call.
        err, yielded = coroutine.resume(co, arg())
    elseif arg_t == "table" then
        -- Callback table.
        err, yielded = coroutine.resume(co, unpack(arg))
    else
        -- Plain resume.
        err, yielded = coroutine.resume(co, arg)
    end
    st = coroutine.status(co)
    if st == "suspended" then
        local yield_t = type(yielded)
        if instanceOf(coctx.CoroutineContext, yielded) then
            -- Advanced yield scenario.
            -- Use CouroutineContext as key in Coroutine map.
            self._co_ctxs[yielded] = co
            return 1
        elseif yield_t == "function" then
            -- Schedule coroutine to be run on next iteration with function
            -- as result of yield.
            self._co_cbs[#self._co_cbs + 1] = {co, yielded}
            return 2
        elseif yield_t == "nil" then
            -- Empty yield. Schedule resume on next iteration.
            self._co_cbs[#self._co_cbs + 1] = {co, 0}
            return 3
        else
            -- Invalid yielded value. Schedule resume of coroutine on next
            -- iteration with -1 as result of yield (to represent error).
            self._co_cbs[#self._co_cbs + 1] = {co, function() return -1 end}
            log.warning(string.format(
                "[ioloop.lua] Callback yielded with unsupported value, %s.",
                yield_t))
            return 3
        end
    end
    return 0
end

_Interval = class("_Interval")
function _Interval:initialize(msec, callback, arg)
    self.interval_msec = msec
    self.callback = callback
    self.arg = arg
    self.next_call = util.gettimemonotonic() + self.interval_msec
end

function _Interval:timed_out(time_now)
    if time_now >= self.next_call then
        return 0
    else
        return self.next_call - time_now
    end
end

function _Interval:set_last_call(time_now)
    self.last_interval = time_now
    self.next_call = time_now + self.interval_msec
    return self.next_call - time_now
end


_Timeout = class('_Timeout')
function _Timeout:initialize(timestamp, callback, arg)
    self._timestamp = timestamp or
        error('No timestamp given to _Timeout class')
    self._callback = callback or
        error('No callback given to _Timeout class')
    self._arg = arg
end

function _Timeout:timed_out(time)
    if self._timestamp - time <= 0 then
        return 0
    else
        return self._timestamp - time
    end
end

function _Timeout:callback()
    return self._callback, self._arg
end


if platform.__LINUX__ and not _G.__TURBO_USE_LUASOCKET__ then
    _EPoll_FFI = class('_EPoll_FFI')

    --- Internal class for epoll-based event loop using the epoll_ffi module.
    function _EPoll_FFI:initialize()
        local errno
        self._epoll_fd, errno = epoll_ffi.epoll_create()
        if self._epoll_fd == -1 then
            error("epoll_create failed with errno = " .. errno)
        end
    end

    function _EPoll_FFI:register(fd, events)
        return epoll_ffi.epoll_ctl(self._epoll_fd, epoll_ffi.EPOLL_CTL_ADD,
            fd, events)
    end

    function _EPoll_FFI:modify(fd, events)
        return epoll_ffi.epoll_ctl(self._epoll_fd, epoll_ffi.EPOLL_CTL_MOD,
            fd, events)
    end

    function _EPoll_FFI:unregister(fd)
        return epoll_ffi.epoll_ctl(self._epoll_fd, epoll_ffi.EPOLL_CTL_DEL,
            fd, 0)
    end

    function _EPoll_FFI:poll(timeout)
        return epoll_ffi.epoll_wait(self._epoll_fd, timeout)
    end
end

if _G.__TURBO_USE_LUASOCKET__ then
    _LuaSocketPoll = class("_LuaSocketPoll")

    function _LuaSocketPoll:initialize()
        self.sendt = {}
        self.recvt = {}
    end

    function _LuaSocketPoll:register(fd, events)
        if bit.band(events, ioloop.WRITE) ~= 0 then
            if #self.sendt >= 64 then
                return -1,
                    "More than 64 sockets in select() table. Can not complete."
            end
            table.insert(self.sendt, fd)
        end
        if bit.band(events, ioloop.READ) ~= 0 then
            if #self.recvt >= 64 then
                return -1,
                    "More than 64 sockets in select() table. Can not complete."
            end
            table.insert(self.recvt, fd)
        end
        return 0, nil
    end

    function _LuaSocketPoll:unregister(fd)
        for i=1, #self.sendt, 1 do
            if self.sendt[i] == fd then
                table.remove(self.sendt, i)
            end
        end
        for i=1, #self.recvt, 1 do
            if self.recvt[i] == fd then
                table.remove(self.recvt, i)
            end
        end
        return 0, nil
    end

    function _LuaSocketPoll:modify(fd, events)
        for i=1, #self.sendt, 1 do
            if self.sendt[i] == fd then
                table.remove(self.sendt, i)
            end
        end
        for i=1, #self.recvt, 1 do
            if self.recvt[i] == fd then
                table.remove(self.recvt, i)
            end
        end
        if bit.band(events, ioloop.WRITE) ~= 0 then
            if #self.sendt >= 64 then
                return -1,
                    "More than 64 sockets in select() table. Can not complete."
            end
            table.insert(self.sendt, fd)
        end
        if bit.band(events, ioloop.READ) ~= 0 then
            if #self.recvt >= 64 then
                return -1,
                    "More than 64 sockets in select() table. Can not complete."
            end
            table.insert(self.recvt, fd)
        end
        return 0, nil
    end

    function _LuaSocketPoll:poll(timeout)
        return luasocket.select(self.recvt, self.sendt, timeout)
    end
end

return ioloop

