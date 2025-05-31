--- Turbo.lua IO Stream module.
-- High-level wrappers for asynchronous socket communication.
-- All API's are callback based and depend on the __Turbo IOLoop module__.
--
-- Implementations available:
--
-- * IOStream, non-blocking sockets.
-- * SSLIOStream, non-blocking SSL sockets using OpenSSL.
--
-- Copyright 2011 - 2015 John Abrahamsen
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


local log =         require "turbo.log"
local ioloop =      require "turbo.ioloop"
local deque =       require "turbo.structs.deque"
local buffer =      require "turbo.structs.buffer"
local socket =      require "turbo.socket_ffi"
local sockutils =   require "turbo.sockutil"
local util =        require "turbo.util"
local signal =      require "turbo.signal"
-- __Global value__ _G.TURBO_SSL allows the user to enable the SSL module.
local crypto =      require "turbo.crypto"
local platform =    require "turbo.platform"
local sockutil =    require "turbo.sockutil"
local coctx =       require "turbo.coctx"
local bit =         jit and require "bit" or require "bit32"
local ffi =         require "ffi"
local ssl
if (not platform.__LINUX__ or _G.__TURBO_USE_LUASOCKET__) and _G.TURBO_SSL then
    -- Non Linux OS uses LuaSec instead of OpenSSL library directly.
    -- As that is made to work with the LuaSocket module.
    -- https://github.com/brunoos/luasec
    ssl = require "ssl"
end
require "turbo.cdef"
require "turbo.3rdparty.middleclass"

local SOCK_STREAM, AF_UNSPEC, EWOULDBLOCK, EINPROGRESS, ECONNRESET, EPIPE,
    EAGAIN, EAI_AGAIN

if platform.__LINUX__  and not _G.__TURBO_USE_LUASOCKET__ then
    SOCK_STREAM = socket.SOCK_STREAM
    AF_UNSPEC =   socket.AF_UNSPEC
    EWOULDBLOCK = socket.EWOULDBLOCK
    EINPROGRESS = socket.EINPROGRESS
    ECONNRESET =  socket.ECONNRESET
    EPIPE =       socket.EPIPE
    EAGAIN =      socket.EAGAIN
    EAI_AGAIN =   socket.EAI_AGAIN
end

local bitor, bitand, min, max =  bit.bor, bit.band, math.min, math.max
local C = ffi.C

-- __Global value__ _G.TURBO_SOCKET_BUFFER_SZ allows the user to set
-- his own socket buffer size to be used by the module. Defaults to
-- (16384+1024) bytes, which is the default max used by axTLS.
_G.TURBO_SOCKET_BUFFER_SZ = _G.TURBO_SOCKET_BUFFER_SZ or (16384+1024)
local TURBO_SOCKET_BUFFER_SZ =  _G.TURBO_SOCKET_BUFFER_SZ
local buf
if platform.__LINUX__  and not _G.__TURBO_USE_LUASOCKET__ then
    buf = ffi.new("char[?]", TURBO_SOCKET_BUFFER_SZ)
end

local iostream = {} -- iostream namespace

--- The IOStream class is implemented through the use of the IOLoop class,
-- and are utilized e.g in the RequestHandler class and its subclasses.
-- They provide a non-blocking interface and support callbacks for most of
-- its operations. For read operations the class supports methods suchs as
-- read until delimiter, read n bytes and read until close. The class has
-- its own write buffer and there is no need to buffer data at any other level.
-- The default maximum write buffer is defined to 100 MB. This can be
-- defined on class initialization.
iostream.IOStream = class('IOStream')

--- Create a new IOStream instance.
-- @param fd (Number) File descriptor, either open or closed. If closed then,
-- the IOStream:connect() method can be used to connect.
-- @param io_loop (IOLoop object) IOLoop class instance to use for event
-- processing. If none is set then the global instance is used, see the
-- ioloop.instance() function.
-- @param max_buffer_size (Number) The maximum number of bytes that can be
-- held in internal buffer before flushing must occur.
-- If none is set, 104857600 are used as default.
function iostream.IOStream:initialize(fd, io_loop, max_buffer_size, args)
    self.socket = assert(fd, "Fd is not a number.")
    self.io_loop = io_loop or ioloop.instance()
    self.max_buffer_size = max_buffer_size or 1024*1024*128
    self.args = args or {}
    self._read_buffer = buffer(1024)
    self._read_buffer_size = 0
    self._read_buffer_offset = 0
    self._read_scan_offset = 0
    self._write_buffer = buffer(1024)
    self._write_buffer_size = 0
    self._write_buffer_offset = 0
    self._pending_callbacks = 0
    self._read_until_close = false
    self._connecting = false
    if platform.__LINUX__ and not _G.__TURBO_USE_LUASOCKET__ then
        local rc, msg = socket.set_nonblock_flag(self.socket)
        if rc == -1 then
            error("[iostream.lua] " .. msg)
        end
    end
end

--- Connect to a address without blocking.
-- @param address (String)  The host to connect to. Either hostname or IP.
-- @param port (Number)  The port to connect to. E.g 80.
-- @param family (Number)  Socket family. Optional. Pass nil to guess.
-- @param callback (Function)  Optional callback for "on successfull connect".
-- @param fail_callback (Function) Optional callback for "on error".
-- @param arg Optional argument for callback.
if platform.__LINUX__ and not _G.__TURBO_USE_LUASOCKET__ then
    function iostream.IOStream:connect(address, port, family,
        callback, fail_callback, arg)
        assert(type(address) == "string",
            "Address is not a string.")
        assert(type(port) == "number",
            "Port is not a number.")
        assert((not family or type(family) == "number"),
            "Family is not a number or nil")
        self._connect_fail_callback = fail_callback
        self._connecting = true
        self._connect_callback = callback
        self._connect_callback_arg = arg
        local servinfo, sockaddr
        local status, err = pcall(function()
            local dns = iostream.DNSResolv(self.io_loop, self.args)
            servinfo, sockaddr = dns:resolv(address, port, family)
        end)
        if not status then
            self:_handle_connect_fail(err or "DNS resolv error")
            return
        end
        local ai, err = sockutils.connect_addrinfo(
                self.socket, servinfo)
        if not ai then
            self:_handle_connect_fail(
                "Could not connect to remote server. " .. (err or ""))
            return
        end
        self:_add_io_state(ioloop.WRITE)
        return 0 -- Too avoid breaking backwards compability.
    end
else
    function iostream.IOStream:connect(address, port, family,
        callback, fail_callback, arg)
        assert(type(address) == "string",
            "Address is not a string")
        assert(type(port) == "number",
            "Port is not a number")
        assert((not family or type(family) == "number"),
            "Family is not a number or nil")
        self._connect_fail_callback = fail_callback
        self._connect_callback = callback
        self._connect_callback_arg = arg
        self._connecting = true
        local _, err = self.socket:connect(address, port)
        if err ~= "Operation already in progress" and err ~= "timeout" then
            self._handle_connect_fail(err)
            return
        end
        self.address = address
        self.port = port
        self:_add_io_state(ioloop.WRITE)
        return 0  -- Too avoid breaking backwards compability.
    end
end

--- Read until delimiter, then call callback with receive data. The callback
-- receives the data read as a parameter. Delimiter is plain text, and does
-- not support Lua patterns. See read_until_pattern for that functionality.
-- read_until should be used instead of read_until_pattern wherever possible
-- because of the overhead of doing pattern matching.
-- @param delimiter (String) Delimiter sequence, text or binary.
-- @param callback (Function) Callback function.
-- @param arg Optional argument for callback. If arg is given then it will
-- be the first argument for the callback and the data will be the second.
function iostream.IOStream:read_until(delimiter, callback, arg)
    assert((not self._read_callback), "Already reading.")
    self._read_delimiter = delimiter
    self._read_callback = callback
    self._read_callback_arg = arg
    self._read_scan_offset = 0
    self:_initial_read()
end

--- Read until pattern is matched, then call callback with receive data.
-- The callback receives the data read as a parameter. If you only are
-- doing plain text matching then using read_until is recommended for
-- less overhead.
-- @param pattern (String) Lua pattern string.
-- @param callback (Function) Callback function.
-- @param arg Optional argument for callback. If arg is given then it will
-- be the first argument for the callback and the data will be the second.
function iostream.IOStream:read_until_pattern(pattern, callback, arg)
    assert(type(pattern) == "string", "Pattern, is not a string.")
    self._read_callback = callback
    self._read_callback_arg = arg
    self._read_pattern = pattern
    self._read_scan_offset = 0
    self:_initial_read()
end

--- Call callback when we read the given number of bytes.
-- If a streaming_callback argument is given, it will be called with chunks
-- of data as they become available, and the argument to the final call to
-- callback will be empty.
-- @param num_bytes (Number) The amount of bytes to read.
-- @param callback (Function) Callback function.
-- @param arg Optional argument for callback. If arg is given then it will
-- be the first argument for the callback and the data will be the second.
-- @param streaming_callback (Function) Optional callback to be called as
-- chunks become available.
-- @param streaming_arg Optional argument for callback. If arg is given then
-- it will be the first argument for the callback and the data will be the
-- second.
function iostream.IOStream:read_bytes(num_bytes, callback, arg,
    streaming_callback, streaming_arg)
    assert((not self._read_callback), "Already reading.")
    assert(type(num_bytes) == 'number',
        'argument #1, num_bytes, is not a number')
    self._read_bytes = num_bytes
    self._read_callback = callback
    self._read_callback_arg = arg
    self._streaming_callback = streaming_callback
    self._streaming_callback_arg = streaming_arg
    self:_initial_read()
end


--- Reads all data from the socket until it is closed.
-- If a streaming_callback argument is given, it will be called with chunks of
-- data as they become available, and the argument to the final call to
-- callback will contain the final chunk. This method respects the
-- max_buffer_size set in the IOStream instance.
-- @param callback (Function) Callback function.
-- @param arg Optional argument for callback. If arg is given then it will
-- be the first argument for the callback and the data will be the second.
-- @param streaming_callback (Funcion) Optional callback to be called as
-- chunks become available.
-- @param streaming_arg Optional argument for callback. If arg is given then
-- it will be the first argument for the callback and the data will be the
-- second.
function iostream.IOStream:read_until_close(callback, arg, streaming_callback,
    streaming_arg)
    if self._read_callback then
        error("Already reading.")
    end
    if self:closed() then
        self:_run_callback(callback, arg,
            self:_consume(self._read_buffer_size))
        return
    end
    self._read_until_close = true
    self._read_callback = callback
    self._read_callback_arg = arg
    self._streaming_callback = streaming_callback
    self._streaming_callback_arg = streaming_arg
    self:_add_io_state(ioloop.READ)
end

--- Write the given data to the stream.
-- If callback is given, we call it when all of the buffered write data has
-- been successfully written to the stream. If there was previously buffered
-- write data and an old write callback, that callback is simply overwritten
-- with this new callback.
-- @param data (String) Data to write to stream.
-- @param callback (Function) Optional callback to call when chunk is flushed.
-- @param arg Optional argument for callback.
function iostream.IOStream:write(data, callback, arg)
    if self._const_write_buffer then
        error(string.format("\
            Can not perform write when there is a ongoing \
            zero copy write operation. At offset %d of %d bytes",
            tonumber(self._write_buffer_offset),
            tonumber(self._const_write_buffer:len())))
    end
    self:_check_closed()
    self._write_buffer:append_luastr_right(data)
    self._write_buffer_size = self._write_buffer_size + data:len()
    self._write_callback = callback
    self._write_callback_arg = arg
    self:_add_io_state(ioloop.WRITE)
    self:_maybe_add_error_listener()
end

--- Write the given buffer class instance to the stream.
-- @param buf (Buffer class instance).
-- @param callback (Function) Optional callback to call when chunk is flushed.
-- @param arg Optional argument for callback.
function iostream.IOStream:write_buffer(buf, callback, arg)
    if self._const_write_buffer then
        error(string.format("\
            Can not perform write when there is a ongoing \
            zero copy write operation. At offset %d of %d bytes",
            tonumber(self._write_buffer_offset),
            tonumber(self._const_write_buffer:len())))
    end
    self:_check_closed()
    local ptr, sz = buf:get()
    self._write_buffer:append_right(ptr, sz)
    self._write_buffer_size = self._write_buffer_size + sz
    self._write_callback = callback
    self._write_callback_arg = arg
    self:_add_io_state(ioloop.WRITE)
    self:_maybe_add_error_listener()
end

--- Write the given buffer class instance to the stream without
-- copying. This means that this write MUST complete before any other
-- writes can be performed. There is a barrier in place to stop this from
-- happening. A error is raised if this happens. This method is recommended
-- when you are serving static data, it refrains from copying the contents of
-- the buffer into its internal buffer, at the cost of not allowing
-- more data being added to the internal buffer before this write is finished.
-- @param buf (Buffer class instance) Will not be modified.
-- @param callback (Function) Optional callback to call when chunk is flushed.
-- @param arg Optional argument for callback.
if platform.__LINUX__ and not _G.__TURBO_USE_LUASOCKET__ then
    function iostream.IOStream:write_zero_copy(buf, callback, arg)
        if self._write_buffer_size ~= 0 then
            error(string.format("\
                Can not perform zero copy write when there are \
                unfinished writes in stream. At offset %d of %d bytes. \
                Write buffer size: %d",
                tonumber(self._write_buffer_offset),
                tonumber(self._write_buffer:len()),
                self._write_buffer_size))
        end
        self:_check_closed()
        self._const_write_buffer = buf
        self._write_buffer_offset = 0
        self._write_callback = callback
        self._write_callback_arg = arg
        self:_add_io_state(ioloop.WRITE)
        self:_maybe_add_error_listener()
    end
else
    -- write_zero_copy is not supported on LuaSocket. It gives no
    -- benefit as LuaSocket only deals in Lua strings...
    function iostream.IOStream:write_zero_copy(buf, callback, arg)
        if self._write_buffer_size ~= 0 then
            error(string.format("\
                Can not perform zero copy write when there are \
                unfinished writes in stream. At offset %d of %d bytes. \
                Write buffer size: %d",
                tonumber(self._write_buffer_offset),
                tonumber(self._write_buffer:len()),
                self._write_buffer_size))
        end
        local ptr, sz = buf:get()
        local str = ffi.string(ptr, sz)
        self:write(str, callback, arg)
    end
end

--- Are the stream currently being read from?
-- @return (Boolean) true or false
function iostream.IOStream:reading()
    return self._read_callback and true or false
end

--- Are the stream currently being written too.
-- @return (Boolean) true or false
function iostream.IOStream:writing()
    return self._write_buffer_size ~= 0 or self._const_write_buffer
end

--- Set callback to be called when connection is closed.
-- @param callback (Function) Callback function.
-- @param arg Optional argument for callback.
function iostream.IOStream:set_close_callback(callback, arg)
    self._close_callback = callback
    self._close_callback_arg = arg
end

--- Sets the given callback to be called when the buffer has been exceeded
-- @param callback (Function) Callback function.
-- @param arg Optional argument for callback.
function iostream.IOStream:set_maxed_buffer_callback(callback, arg)
    self._maxb_callback = callback
    self._maxb_callback_arg = arg
end

function iostream.IOStream:set_max_buffer_size(sz)
    if type(sz) ~= "number" then
        return
    end
    if sz < TURBO_SOCKET_BUFFER_SZ then
        log.warning(
            string.format("Max buffer size could not be set to lower value "..
                          "than _G.TURBO_SOCKET_BUFFER_SZ (%dB).",
                          TURBO_SOCKET_BUFFER_SZ + 8))
        sz = TURBO_SOCKET_BUFFER_SZ + 8
    end
    self.max_buffer_size = sz
end

--- Close this stream and clean up.
-- Call close callback if set.
function iostream.IOStream:close()
    if self.socket then
        --log.devel("[iostream.lua] Closing socket " .. tostring(self.socket))
        if self._read_until_close then
            local callback = self._read_callback
            local arg = self._read_callback_arg
            self._read_callback = nil
            self._read_callback_arg = nil
            self._read_until_close = false
            self:_run_callback(callback, arg,
                self:_consume(self._read_buffer_size))
        end
        if self._state then
            self.io_loop:remove_handler(self.socket)
            self._state = nil
        end
        if platform.__LINUX__ and not _G.__TURBO_USE_LUASOCKET__ then
            C.close(self.socket)
        else
            self.socket:close()
        end
        self.socket = nil
        if self._close_callback and self._pending_callbacks == 0 then
            local callback = self._close_callback
            local arg = self._close_callback_arg
            self._close_callback = nil
            self._close_callback_arg = nil
            self:_run_callback(callback, arg)
        end
    end
end

--- Is the stream closed?
-- @return (Boolean) true or false
function iostream.IOStream:closed()
    if self.socket then
        return false
    else
        return true
    end
end

--- Initial inline read for read methods.
-- If read is not possible at this time, it is added to IOLoop.
function iostream.IOStream:_initial_read()
    while true do
        if self:_read_from_buffer() == true then
            return
        end
        self:_check_closed()
        if self:_read_to_buffer() == 0 then
            break
        end
    end
    self:_add_io_state(ioloop.READ)
end

function iostream.IOStream:_handle_connect_fail(err)
    local cb = self._connect_fail_callback
    local arg = self._connect_callback_arg
    self._connect_fail_callback = nil
    self._connect_callback = nil
    self._connect_callback_arg = nil
    self._connecting = false
    self:_run_callback(cb, arg, err)
end

--- Main event handler for the IOStream.
-- @param fd (Number) File descriptor.
-- @param events (Number) Bit mask of available events for given fd.
function iostream.IOStream:_handle_events(fd, events)
    if not self.socket then
        -- Connection has been closed. Can not handle events...
        log.warning(
            string.format("Got events for closed stream on fd %d.", fd))
        return
    end
    -- Handle different events.
    if bitand(events, ioloop.READ) ~= 0 then
        self:_handle_read()
    end
    -- We must check if the socket has been closed after handling
    -- the read!
    if not self.socket then
        return
    end
    if bitand(events, ioloop.WRITE) ~= 0 then
        if self._connecting then
            self:_handle_connect()
        end
        self:_handle_write()
    end
    if not self.socket then
        return
    end
    if bitand(events, ioloop.ERROR) ~= 0 then
        local rc, err = socket.get_socket_error(self.socket)
        if rc == 0 then
            self.error = err
        end
        -- We may have queued up a user callback in _handle_read or
        -- _handle_write, so don't close the IOStream until those
        -- callbacks have had a chance to run.
        self.io_loop:add_callback(self.close, self)
        return
    end
    local state = ioloop.ERROR
    if self:reading() then
        state = bitor(state, ioloop.READ)
    end
    if self:writing() then
        state = bitor(state, ioloop.WRITE)
    end
    if state == ioloop.ERROR then
        state = bitor(state, ioloop.READ)
    end
    if state ~= self._state then
        assert(self._state, "no self._state set")
        self._state = state
        self.io_loop:update_handler(self.socket, self._state)
    end
end

--- Error handler for IOStream callbacks.
local function _run_callback_error_handler(err)
    local thread = coroutine.running()
    local trace = debug.traceback(coroutine.running(), err, 2)
    local _str_borders_down = string.rep("▼", 80)
    local _str_borders_up = string.rep("▲", 80)

    log.error(
        string.format(
            "[iostream.lua] Error in callback. Closing socket, %s is dead.\n%s\n%s\n%s\n",
            thread,
            _str_borders_down,
            trace,
            _str_borders_up))
end

local function _run_callback_protected(call)
    local stream, callback, res, arg = call[1], call[2], call[3], call[4]
    local success = false
    -- Remove 1 pending callback from IOStream instance.
    stream._pending_callbacks = stream._pending_callbacks - 1
    
    if arg then
        -- Callback argument. First argument should be this to allow self
        -- references to be used as argument.
        success = xpcall(
            callback,
            _run_callback_error_handler,
            arg,
            res)
    else
        success = xpcall(
            callback,
            _run_callback_error_handler,
            res)
    end
    if success == false then
        stream:close()
    end
end

function iostream.IOStream:_run_callback(callback, arg, data)
    self:_maybe_add_error_listener()
    self._pending_callbacks = self._pending_callbacks + 1
    -- Add callback to IOLoop instead of calling it straight away.
    -- This is to provide a consistent stack growth, while also
    -- yielding to handle other tasks in the IOLoop.
    self.io_loop:add_callback(_run_callback_protected,
        {self, callback, data, arg})
end

function iostream.IOStream:_maybe_run_close_callback()
    if self:closed() == true and self._close_callback and
        self._pending_callbacks == 0 then
        local cb = self._close_callback
        local arg = self._close_callback_arg
        self._close_callback = nil
        self._close_callback_arg = nil
        self:_run_callback(cb, arg)
        self._read_callback = nil
        self._read_callback_arg = nil
        self._write_callback = nil
        self._write_callback_arg = nil
    end
end

function iostream.IOStream:_handle_read()
    self._pending_callbacks = self._pending_callbacks + 1
    while not self:closed() do
        -- Read from socket until we get EWOULDBLOCK or equivalient.
        if self:_read_to_buffer() == 0 then
            break
        end
        -- Give a chance to run scheduled callback before we read all data.
        if self:_read_from_buffer() == true then
            break
        end
    end
    self._pending_callbacks = self._pending_callbacks - 1
    self:_maybe_run_close_callback()
end

--- Reads from the socket. Return the data chunk or nil if theres nothing to
-- read, in the case of EWOULDBLOCK or equivalent.
-- @return Chunk of data.
if platform.__LINUX__ and not _G.__TURBO_USE_LUASOCKET__ then
    function iostream.IOStream:_read_from_socket()
        local errno
        local buffer_left = self.max_buffer_size - self._read_buffer_size
        if buffer_left == 0 then
            log.devel("Maximum read buffer size reached. Throttling read.")
            if self._maxb_callback then
                self:_run_callback(self._maxb_callback,
                                   self._maxb_callback_arg,
                                   self._read_buffer_size)
            end
            return
        end
        local sz = tonumber(C.recv(self.socket,
                                   buf,
                                   TURBO_SOCKET_BUFFER_SZ < buffer_left and
                                       TURBO_SOCKET_BUFFER_SZ or buffer_left,
                                   0))
        if sz == -1 then
            errno = ffi.errno()
            if errno == EWOULDBLOCK or errno == EAGAIN then
                return
            elseif errno == ECONNRESET then
                self:close()
                return nil
            else
                local fd = self.socket
                self:close()
                error(string.format(
                      "Error when reading from socket %d. Errno: %d. %s",
                      fd,
                      errno,
                      socket.strerror(errno)))
                return
            end
        end
        if sz == 0 then
            self:close()
            return nil
        end
        return buf, sz
    end
else
    function iostream.IOStream:_read_from_socket()
        local errno, closed
        local buffer_left = self.max_buffer_size - self._read_buffer_size
        if buffer_left == 0 then
            log.devel("Maximum read buffer size reached. Throttling read.")
            if self._maxb_callback then
                self:_run_callback(self._maxb_callback,
                                   self._maxb_callback_arg,
                                   self._read_buffer_size)
            end
            return
        end
        -- Put buf in self, to keep reference for ptr after end of function.
        self._luasocket_buf = buffer(
            math.min(TURBO_SOCKET_BUFFER_SZ, tonumber(buffer_left)))
        while true do
            -- Ok, so LuaSocket is not really suited for this stuff,
            -- do consecutive calls to exhaust socket and fill up a buffer...
            -- TODO: Make sure that max buffer size is not exceeded.
            local data, err, partial = self.socket:receive(
                math.min(TURBO_SOCKET_BUFFER_SZ, tonumber(buffer_left)))
            if data then
                self._luasocket_buf:append_luastr_right(data)
            elseif err == "timeout" or err == "wantread" then
                if partial:len() == 0 then
                    break
                else
                    self._luasocket_buf:append_luastr_right(partial)
                end
            elseif err == "closed" then
                -- So this defers somewhat from the FFI version where
                -- a disconnect would be detected by polling instead of
                -- on a read event, so we should run the callback as usual
                -- without reporting error, but rather not accept further
                -- reads or writes
                self._luasocket_buf:append_luastr_right(partial)
                closed = true
                break
            elseif err then
                local fd = self.socket
                self:close()
                error(string.format(
                      "Error when reading from socket %s: %s",
                      fd,
                      err))
            end

        end
        if self._luasocket_buf:len() > 0 then
            local ptr, sz = self._luasocket_buf:get()
            return ptr, sz, closed
        else
            return nil, nil, closed
        end
    end
end

--- Read from the socket and append to the read buffer.
--  @return Amount of bytes appended to self._read_buffer.
function iostream.IOStream:_read_to_buffer()
    local ptr, sz, closed = self:_read_from_socket()
    if not ptr then
        if closed then
            self:close()
            return
        end
        return 0
    end
    self._read_buffer:append_right(ptr, sz)
    self._read_buffer_size = self._read_buffer_size + sz
    if closed then
        self:close()
    end
    if self._read_buffer_size > self.max_buffer_size then
        log.error('Reached maximum read buffer size')
        self:close()
        return
    end
    return sz
end

--- Get the current read buffer pointer and size.
function iostream.IOStream:_get_buffer_ptr()
    local ptr, sz = self._read_buffer:get()
    ptr = ptr + self._read_buffer_offset
    sz = sz - self._read_buffer_offset
    return ptr, sz
end

--- Attempts to complete the currently pending read from the buffer.
-- @return (Boolean) Returns true if the enqued read was completed, else false.
function iostream.IOStream:_read_from_buffer()
    -- Handle streaming callbacks first.
    if self._streaming_callback ~= nil and self._read_buffer_size ~= 0 then
        local bytes_to_consume = self._read_buffer_size
        if self._read_bytes ~= nil then
            bytes_to_consume = min(self._read_bytes, bytes_to_consume)
            self._read_bytes = self._read_bytes - bytes_to_consume
            self:_run_callback(self._streaming_callback,
                self._streaming_callback_arg,
                self:_consume(bytes_to_consume))
        else
            self:_run_callback(self._streaming_callback,
                self._streaming_callback_arg,
                self:_consume(bytes_to_consume))
        end
    end
    -- Handle read_bytes.
    if self._read_bytes ~= nil and
        self._read_buffer_size >= self._read_bytes then
        local num_bytes = self._read_bytes
        local callback = self._read_callback
        local arg = self._read_callback_arg
        self._read_callback = nil
        self._read_callback_arg = nil
        self._streaming_callback = nil
        self._streaming_callback_arg = nil
        self._read_bytes = nil
        self:_run_callback(callback, arg, self:_consume(num_bytes))
        return true
    -- Handle read_until.
    elseif self._read_delimiter ~= nil then
        if self._read_buffer_size ~= 0 then
            local ptr, sz = self:_get_buffer_ptr()
            local delimiter_sz = self._read_delimiter:len()
            local scan_ptr = ptr + self._read_scan_offset
            sz = sz - self._read_scan_offset
            local loc = util.str_find(
                scan_ptr,
                ffi.cast("char *", self._read_delimiter),
                sz,
                delimiter_sz)
            if loc then
                loc = loc - ptr
                local delimiter_end = loc + delimiter_sz
                local callback = self._read_callback
                local arg = self._read_callback_arg
                self._read_callback = nil
                self._read_callback_arg = nil
                self._streaming_callback = nil
                self._streaming_callback_arg = nil
                self._read_delimiter = nil
                self._read_scan_offset = delimiter_end
                if arg then
                    self:_run_callback(callback,
                        arg,
                        self:_consume(delimiter_end))
                else
                    self:_run_callback(callback, self:_consume(delimiter_end))
                end
                return true
            end
            self._read_scan_offset = sz
        end
    -- Handle read_until_pattern.
    elseif self._read_pattern ~= nil then
        if self._read_buffer_size ~= 0 then
            -- Slow buffer to Lua string conversion to support Lua patterns.
            -- Made even worse by a new allocation in self:_consume of a
            -- different size.
            local ptr, sz = self:_get_buffer_ptr()
            ptr = ptr + self._read_scan_offset
            sz = sz - self._read_scan_offset
            local chunk = ffi.string(ptr, sz)
            local s_start, s_end = chunk:find(self._read_pattern, 1, false)
            if s_start then
                local callback = self._read_callback
                local arg = self._read_callback_arg
                self._read_callback = nil
                self._read_callback_arg = nil
                self._streaming_callback = nil
                self._streaming_callback_arg = nil
                self._read_pattern = nil
                self:_run_callback(callback, arg, self:_consume(
                    s_end + self._read_scan_offset))
                self._read_scan_offset = s_end
                return true
            end
            self._read_scan_offset = sz
        end
    end
    return false
end

if platform.__LINUX__ and not _G.__TURBO_USE_LUASOCKET__ then
    function iostream.IOStream:_handle_write_nonconst()
        local errno, fd
        local ptr, sz = self._write_buffer:get()
        local buf = ptr + self._write_buffer_offset
        local num_bytes = tonumber(C.send(
            self.socket,
            buf,
            self._write_buffer_size,
            0))
        if num_bytes == -1 then
            errno = ffi.errno()
            if errno == EWOULDBLOCK or errno == EAGAIN then
                return
            elseif errno == EPIPE or errno == ECONNRESET then
                -- Connection reset. Close the socket.
                fd = self.socket
                self:close()
                log.warning(string.format(
                    "Connection closed on fd %d.",
                    fd))
                return
            end
            fd = self.socket
            self:close()
            error(string.format("Error when writing to fd %d, %s",
                fd,
                socket.strerror(errno)))
        end
        if num_bytes == 0 then
            return
        end
        self._write_buffer_offset = self._write_buffer_offset + num_bytes
        self._write_buffer_size = self._write_buffer_size - num_bytes
        if self._write_buffer_size == 0 then
            -- Buffer reached end. Reset offset and size.
            self._write_buffer:clear()
            self._write_buffer_offset = 0
            if self._write_callback then
                -- Current buffer completely flushed.
                local callback = self._write_callback
                local arg = self._write_callback_arg
                self._write_callback = nil
                self._write_callback_arg = nil
                self:_run_callback(callback, arg)
            end
        end
    end

    function iostream.IOStream:_handle_write_const()
        local errno, fd
        -- The reference is removed once the write is complete.
        local buf, sz = self._const_write_buffer:get()
        local ptr = buf + self._write_buffer_offset
        local _sz = sz - self._write_buffer_offset
        local num_bytes = C.send(
            self.socket,
            ptr,
            _sz,
            0)
        if num_bytes == -1 then
            errno = ffi.errno()
            if errno == EWOULDBLOCK or errno == EAGAIN then
                return
            elseif errno == EPIPE or errno == ECONNRESET then
                -- Connection reset. Close the socket.
                fd = self.socket
                self:close()
                log.warning(string.format(
                    "Connection closed on fd %d.",
                    fd))
                return
            end
            fd = self.socket
            self:close()
            error(string.format("Error when writing to fd %d, %s",
                fd,
                socket.strerror(errno)))
        end
        if num_bytes == 0 then
            return
        end
        self._write_buffer_offset = self._write_buffer_offset + num_bytes
        if sz == self._write_buffer_offset then
            -- Buffer reached end. Remove reference to const write buffer.
            self._write_buffer_offset = 0
            self._const_write_buffer = nil
            if self._write_callback then
                -- Current buffer completely flushed.
                local callback = self._write_callback
                local arg = self._write_callback_arg
                self._write_callback = nil
                self._write_callback_arg = nil
                self:_run_callback(callback, arg)
            end
        end
    end
else
    function iostream.IOStream:_handle_write_nonconst()
        local errno, fd
        local ptr, sz = self._write_buffer:get()
        local buf = ptr + self._write_buffer_offset
        -- Not very optimal to create a new string for LuaSocket.
        local num_bytes, err = self.socket:send(
            ffi.string(buf, math.min(self._write_buffer_size, 1024*128)))
        if err then
            if err == "closed" then
                log.warning(string.format(
                    "Connection closed on fd %s.",
                    fd))
            else
                log.warning(string.format(
                    "Error on fd %s. %s",
                    fd,
                    err))
            end
            fd = self.socket
            self:close()
            return
        end
        self._write_buffer_offset = self._write_buffer_offset + num_bytes
        self._write_buffer_size = self._write_buffer_size - num_bytes
        if self._write_buffer_size == 0 then
            -- Buffer reached end. Reset offset and size.
            self._write_buffer:clear()
            self._write_buffer_offset = 0
            if self._write_callback then
                -- Current buffer completely flushed.
                local callback = self._write_callback
                local arg = self._write_callback_arg
                self._write_callback = nil
                self._write_callback_arg = nil
                self:_run_callback(callback, arg)
            end
        end
    end

    -- _handle_write_const is not implemented for LuaSocket as it gives no real
    -- benefit. Function calls to const writes are rewritten to nonconst.
    function iostream.IOStream:_handle_write_const()
        error("Not implemented for LuaSocket Turbo.")
    end

end

function iostream.IOStream:_handle_write()
    if not self.socket then
        return
    end
    if self._const_write_buffer then
        self:_handle_write_const()
    else
        self:_handle_write_nonconst()
    end
end

--- Add IO state to IOLoop.
-- @param state (Number) IOLoop state to set.
function iostream.IOStream:_add_io_state(state)
    if not self.socket then
        -- Connection has been closed, ignore request.
        return
    end
    if not self._state then
        self._state = bitor(ioloop.ERROR, state)
        self.io_loop:add_handler(self.socket,
            self._state,
            self._handle_events,
            self)
    elseif bitand(self._state, state) == 0 then
        self._state = bitor(self._state, state)
        self.io_loop:update_handler(self.socket, self._state)
    end
end

function iostream.IOStream:_consume(loc)
    if loc == 0 then
        return ""
    end
    self._read_buffer_size = self._read_buffer_size - loc
    local ptr, sz = self._read_buffer:get()
    local chunk = ffi.string(ptr + self._read_buffer_offset, loc)
    self._read_buffer_offset = self._read_buffer_offset + loc
    if self._read_buffer_offset == sz then
        -- Buffer reached end. Reset offset and size.
        -- We could in theory shrink buffer here but, it is faster
        -- to let it stay as is.
        self._read_buffer:clear()
        self._read_buffer_offset = 0
    end
    return chunk
end

function iostream.IOStream:_check_closed()
    if not self.socket then
        error("Socket operation on closed stream.")
    end
end

function iostream.IOStream:_maybe_add_error_listener()
    if self._state == nil and self._pending_callbacks == 0 then
        if self.socket == nil then
            local callback = self._close_callback
            local arg = self._close_callback_arg
            if callback ~= nil then
                self._close_callback = nil
                self._close_callback_arg = nil
                self:_run_callback(callback, arg)
            end
        else
            self:_add_io_state(ioloop.READ)
        end
    end
end

if platform.__LINUX__  and not _G.__TURBO_USE_LUASOCKET__ then
    function iostream.IOStream:_handle_connect()
        local rc, sockerr = socket.get_socket_error(self.socket)
        if rc == -1 then
            error("[iostream.lua] Could not get socket errors, for fd " ..
                self.socket)
        else
            if sockerr ~= 0 then
                local fd = self.socket
                self:close()
                local strerror = socket.strerror(sockerr)
                if self._connect_fail_callback then
                    if self._connect_callback_arg then
                        self._connect_fail_callback(
                            self._connect_callback_arg,
                            sockerr,
                            strerror)
                    else
                        self._connect_fail_callback(sockerr, strerror)
                    end
                else
                    error(string.format(
                        "[iostream.lua] Connect failed: %s, for fd %d",
                        socket.strerror(sockerr), fd))
                end
                return
            end
        end
        if self._connect_callback then
            local callback = self._connect_callback
            local arg = self._connect_callback_arg
            self._connect_callback = nil
            self._connect_callback_arg = nil
            self:_run_callback(callback, arg)
        end
        self._connecting = false
    end
else
    function iostream.IOStream:_handle_connect()
        local _, err = self.socket:connect(self.address, self.port)
        -- It seems the "LuaSocket way" is to not run get_socket_error, but
        -- call connect once again and check for "already connected" return.
        -- If returns a different error than this string then it has failed,
        -- to connect.
        if err and err ~= "already connected" then
            local fd = self.socket
            self:close()
            if self._connect_fail_callback then
                if self._connect_callback_arg then
                    self._connect_fail_callback(
                        self._connect_callback_arg,
                        -1, -- Kind of bad rc. What to do?
                        err)
                else
                    self._connect_fail_callback(sockerr, strerror)
                end
            else
                error(string.format(
                    "[iostream.lua] Connect failed: %s, for fd %s",
                    err, fd))
            end
            return
        end
        if self._connect_callback then
            local callback = self._connect_callback
            local arg = self._connect_callback_arg
            self._connect_callback = nil
            self._connect_callback_arg = nil
            self:_run_callback(callback, arg)
        end
        self._connecting = false
    end
end

if _G.TURBO_SSL and platform.__LINUX__  and not _G.__TURBO_USE_LUASOCKET__ then
    --- SSLIOStream, non-blocking SSL sockets using OpenSSL
    -- The class is a extention of the IOStream class and uses
    -- OpenSSL for its implementation. Obviously a SSL tunnel
    -- software is a more optimal approach than this, as there
    -- is quite a bit of overhead in handling SSL connections.
    -- For this class to be available, the global _G.TURBO_SSL
    -- must be set.
    iostream.SSLIOStream = class('SSLIOStream', iostream.IOStream)

    --- Initialize a new SSLIOStream class instance.
    -- @param fd (Number) File descriptor, either open or closed. If closed then,
    -- the IOStream:connect() method can be used to connect.
    -- @param ssl_options (Table) SSL options table contains, public and private
    -- keys and a SSL_context pointer.
    -- @param io_loop (IOLoop object) IOLoop class instance to use for event
    -- processing. If none is set then the global instance is used, see the
    -- ioloop.instance() function.
    -- @param max_buffer_size (Number) The maximum number of bytes that can be
    -- held in internal buffer before flushing must occur.
    -- If none is set, 104857600 are used as default.
    function iostream.SSLIOStream:initialize(fd, ssl_options, io_loop,
        max_buffer_size, args)
        self._ssl_options = ssl_options
        -- ssl_options should contain keys with values:
        -- "_ssl_ctx" = SSL_CTX pointer created with context functions in
        -- crypto.lua.
        -- "_type" = Optional number, 0 or 1. 0 indicates that the context
        -- is a server context, and 1 indicates a client context.
        -- Other keys may be stored in the table, but are simply ignored.
        self._ssl = nil
        iostream.IOStream.initialize(self, fd, io_loop, max_buffer_size, args)
        self._ssl_accepting = true
        self._ssl_connect_callback = nil
        self._ssl_connect_callback_arg = arg
        self._server_hostname = nil
    end

    function iostream.SSLIOStream:connect(address, port, family, verify, callback,
        errhandler, arg)
        -- We steal the on_connect callback from the caller. And make sure that we
        -- do handshaking before anything else.
        self._ssl_connect_callback = callback
        self._ssl_connect_errhandler = errhandler
        self._ssl_connect_callback_arg = arg
        self._ssl_hostname = address
        self._ssl_verify = verify == nil and true or verify
        return iostream.IOStream.connect(self,
            address,
            port,
            family,
            self._handle_connect,
            self._connect_errhandler,
            self)
    end

    function iostream.SSLIOStream:_connect_errhandler()
        if self._ssl_connect_errhandler then
            local errhandler = self._ssl_connect_errhandler
            local arg = self._ssl_connect_callback_arg
            self._ssl_connect_errhandler = nil
            self._ssl_connect_callback_arg = nil
            self._ssl_connect_callback = nil
            errhandler(arg)
        end
    end

    function iostream.SSLIOStream:_do_ssl_handshake()
        local ssl = self._ssl
        local client = self._ssl_options._type == 1

        -- create new SSL connection only once
        if not ssl then
            ssl = crypto.ssl_new(self._ssl_options._ssl_ctx, self.socket, client)
            self._ssl = ssl
        end
        -- do the SSL handshaking, returns true when connected, otherwise false
        if crypto.ssl_do_handshake(self) then
            -- Connection established. Set accepting flag to false and thereby
            -- allow writes and reads over the socket.
            self._ssl_accepting = false
            if self._ssl_connect_callback then
                local _ssl_connect_callback = self._ssl_connect_callback
                local _ssl_connect_callback_arg = self._ssl_connect_callback_arg
                self._ssl_connect_callback = nil
                self._ssl_connect_callback_arg = nil
                _ssl_connect_callback(_ssl_connect_callback_arg)
            end
        end
    end

    function iostream.SSLIOStream:_handle_read()
        if self._ssl_accepting == true then
            self:_do_ssl_handshake()
            return
        end
        iostream.IOStream._handle_read(self)
    end

    function iostream.SSLIOStream:_handle_connect()
        if self._connecting == true then
            local rc, sockerr = socket.get_socket_error(self.socket)
            if rc == -1 then
                error("[iostream.lua] Could not get socket errors, for fd " ..
                    self.socket)
            else
                if sockerr ~= 0 then
                    local fd = self.socket
                    self:close()
                    local strerror = socket.strerror(sockerr)
                    if self._ssl_connect_errhandler then
                        local errhandler = self._ssl_connect_errhandler
                        local arg = self._ssl_connect_callback_arg
                        self._ssl_connect_errhandler = nil
                        self._ssl_connect_callback_arg = nil
                        self._ssl_connect_callback = nil
                        errhandler(arg, sockerr, strerror)
                    else
                        error(string.format(
                            "[iostream.lua] Connect failed: %s, for fd %d",
                            socket.strerror(sockerr),
                            fd))
                    end
                    return
                end
            end
            self._connecting = false
        end
        self:_do_ssl_handshake()
    end

    function iostream.SSLIOStream:_read_from_socket()
        if self._ssl_accepting == true then
            -- If the handshake has not been completed do not allow
            -- any reads to be done...
            return
        end
        local errno
        local err

        local sz = crypto.SSL_read(self._ssl, buf, _G.TURBO_SOCKET_BUFFER_SZ)
        if sz == -1 then
            err = crypto.SSL_get_error(self._ssl, sz)
            if err == crypto.SSL_ERROR_SYSCALL then
                errno = ffi.errno()
                if errno == EWOULDBLOCK or errno == EAGAIN then
                    return
                else
                    local fd = self.socket
                    self:close()
                    error(string.format(
                        "Error when reading from socket %d. Errno: %d. %s",
                        fd,
                        errno,
                        socket.strerror(errno)))
                end
            elseif err == crypto.SSL_ERROR_WANT_READ then
                return
            else
                -- local fd = self.socket
                local ssl_err = crypto.ERR_get_error()
                local ssl_str_err = crypto.ERR_error_string(ssl_err)
                self:close()
                error(string.format("SSL error. %s",
                    ssl_str_err))
            end
        end
        if sz == 0 then
            self:close()
            return
        end
        return buf, sz
    end

    function iostream.SSLIOStream:_handle_write_nonconst()
        if self._ssl_accepting == true then
            -- If the handshake has not been completed do not allow any writes to
            -- be done.
            return nil
        end

        local ptr = self._write_buffer:get()
        ptr = ptr + self._write_buffer_offset
        local n = crypto.SSL_write(self._ssl, ptr, self._write_buffer_size)
        if n == -1 then
            local err = crypto.SSL_get_error(self._ssl, n)
            if err == crypto.SSL_ERROR_SYSCALL then
                local errno = ffi.errno()
                if errno == EWOULDBLOCK or errno == EAGAIN then
                    return
                else
                    local fd = self.socket
                    self:close()
                    error(string.format(
                        "Error when writing to socket %d. Errno: %d. %s",
                        fd,
                        errno,
                        socket.strerror(errno)))
                end
            elseif err == crypto.SSL_ERROR_WANT_WRITE then
                return
            else
                -- local fd = self.socket
                local ssl_err = crypto.ERR_get_error()
                local ssl_str_err = crypto.ERR_error_string(ssl_err)
                self:close()
                error(string.format("SSL error. %s",
                    ssl_str_err))
            end
        end
        if n == 0 then
            return
        end
        self._write_buffer_offset = self._write_buffer_offset + n
        self._write_buffer_size = self._write_buffer_size - n
        if self._write_buffer_size == 0 then
            -- Buffer reached end. Reset offset and size.
            self._write_buffer:clear()
            self._write_buffer_offset = 0
            if self._write_callback then
                -- Current buffer completely flushed.
                local callback = self._write_callback
                local arg = self._write_callback_arg
                self._write_callback = nil
                self._write_callback_arg = nil
                self:_run_callback(callback, arg)
            end
        end
    end

    function iostream.SSLIOStream:_handle_write_const()
        if self._ssl_accepting == true then
            -- If the handshake has not been completed do not allow any writes to
            -- be done.
            return nil
        end

        local buf, sz = self._const_write_buffer:get()
        buf = buf + self._write_buffer_offset
        sz = sz - self._write_buffer_offset
        local n = crypto.SSL_write(self._ssl, buf, sz)
        if n == -1 then
            local err = crypto.SSL_get_error(self._ssl, n)
            if err == crypto.SSL_ERROR_SYSCALL then
                local errno = ffi.errno()
                if errno == EWOULDBLOCK or errno == EAGAIN then
                    return
                else
                    local fd = self.socket
                    self:close()
                    error(string.format(
                        "Error when writing to socket %d. Errno: %d. %s",
                        fd,
                        errno,
                        socket.strerror(errno)))
                end
            elseif err == crypto.SSL_ERROR_WANT_WRITE then
                return
            else
                -- local fd = self.socket
                local ssl_err = crypto.ERR_get_error()
                local ssl_str_err = crypto.ERR_error_string(ssl_err)
                self:close()
                error(string.format("SSL error. %s",
                    ssl_str_err))
            end
        end
        if n == 0 then
            return
        end
        self._write_buffer_offset = self._write_buffer_offset + n
        if sz == self._write_buffer_offset then
            -- Buffer reached end. Remove reference to const write buffer.
            self._write_buffer_offset = 0
            self._const_write_buffer = nil
            if self._write_callback then
                -- Current buffer completely flushed.
                local callback = self._write_callback
                local arg = self._write_callback_arg
                self._write_callback = nil
                self._write_callback_arg = nil
                self:_run_callback(callback, arg)
            end
        end
    end
elseif _G.TURBO_SSL then
    iostream.SSLIOStream = class('SSLIOStream', iostream.IOStream)

    function iostream.SSLIOStream:initialize(fd, ssl_options, io_loop,
        max_buffer_size)
        self._ssl_options = ssl_options
        -- ssl_options should contain keys with values:
        -- "_ssl_ctx" = SSL_CTX pointer created with context functions in
        -- crypto.lua.
        -- "_type" = Optional number, 0 or 1. 0 indicates that the context
        -- is a server context, and 1 indicates a client context.
        -- Other keys may be stored in the table, but are simply ignored.
        self._ssl = nil
        iostream.IOStream.initialize(self, fd, io_loop, max_buffer_size)
        self._ssl_accepting = true
        self._ssl_connect_callback = nil
        self._ssl_connect_callback_arg = arg
        self._server_hostname = nil
    end

    function iostream.SSLIOStream:connect(address, port, family, verify, callback,
        errhandler, arg)
        -- We steal the on_connect callback from the caller. And make sure that we
        -- do handshaking before anything else.
        self._ssl_connect_callback = callback
        self._ssl_connect_errhandler = errhandler
        self._ssl_connect_callback_arg = arg
        self._ssl_hostname = address
        self._ssl_verify = verify == nil and true or verify
        return iostream.IOStream.connect(self,
            address,
            port,
            family,
            self._handle_connect,
            self._connect_errhandler,
            self)
    end

    function iostream.SSLIOStream:_connect_errhandler()
        if self._ssl_connect_errhandler then
            local errhandler = self._ssl_connect_errhandler
            local arg = self._ssl_connect_callback_arg
            self._ssl_connect_errhandler = nil
            self._ssl_connect_callback_arg = nil
            self._ssl_connect_callback = nil
            errhandler(arg)
        end
    end

    function iostream.SSLIOStream:_do_ssl_handshake()
        local ssl = self._ssl
        local client = self._ssl_options._type == 1
        -- create new SSL connection only once
        if not ssl then
            ssl = crypto.ssl_new(self._ssl_options._ssl_ctx, self.socket, client)
            self._ssl = ssl
            -- Replace LuaSocket object with wrapped one...
            self.io_loop:remove_handler(self.socket)
            self.socket = ssl
            self.io_loop:add_handler(self.socket, ioloop.READ, self._handle_events, self)
        end
        -- do the SSL handshaking, returns true when connected, otherwise false
        local res, err = crypto.ssl_do_handshake(self)
        if res then
            -- Connection established. Set accepting flag to false and thereby
            -- allow writes and reads over the socket.
            self._ssl_accepting = false
            if self._ssl_connect_callback then
                local _ssl_connect_callback = self._ssl_connect_callback
                local _ssl_connect_callback_arg = self._ssl_connect_callback_arg
                self._ssl_connect_callback = nil
                self._ssl_connect_callback_arg = nil
                _ssl_connect_callback(_ssl_connect_callback_arg)
            end
        elseif err == "wantread" then
            self:_add_io_state(ioloop.READ)
        else
            self:close()
        end
    end

    function iostream.SSLIOStream:_handle_read()
        if self._ssl_accepting == true then
            self:_do_ssl_handshake()
            return
        end
        return iostream.IOStream._handle_read(self)
    end

    function iostream.SSLIOStream:_read_from_socket()
        if self._ssl_accepting == true then
            -- If the handshake has not been completed do not allow
            -- any reads to be done...
            return
        end
        return iostream.IOStream._read_from_socket(self)
    end

    function iostream.SSLIOStream:_handle_write_nonconst()
        if self._ssl_accepting == true then
            -- If the handshake has not been completed do not allow any writes to
            -- be done.
            return nil
        end
        return iostream.IOStream._handle_write_nonconst(self)
    end

    function iostream.SSLIOStream:_handle_write_const()
        if self._ssl_accepting == true then
            -- If the handshake has not been completed do not allow any writes to
            -- be done.
            return nil
        end
        return iostream.IOStream._handle_write_const(self)
    end

    function iostream.SSLIOStream:_handle_connect()
        if self._connecting == true then
            local _, err = self.socket:connect(self.address, self.port)
            if err and err ~= "already connected" then
                local fd = self.socket
                self:close()
                if self._ssl_connect_errhandler then
                    local errhandler = self._ssl_connect_errhandler
                    local arg = self._ssl_connect_callback_arg
                    self._ssl_connect_errhandler = nil
                    self._ssl_connect_callback_arg = nil
                    self._ssl_connect_callback = nil
                    errhandler(arg, -1, err)
                else
                    error(string.format(
                        "[iostream.lua] Connect failed: %s, for fd %s",
                        err,
                        fd))
                end
                return
            end
            self._connecting = false
        end
        self:_do_ssl_handshake()
    end

end

if platform.__LINUX__ and not _G.__TURBO_USE_LUASOCKET__ then
    function iostream.DNSCache()
        return setmetatable({},
        {
        })
    end
    iostream._dns_cache = iostream.DNSCache() -- Static object cache :)
    iostream.DNSResolv = class("DNSResolv")

    function iostream.DNSResolv:initialize(io_loop, args)
        self.io_loop = io_loop or ioloop.instance()
        self.args = args or {}
    end

    function iostream.DNSResolv:resolv(address, port, family)
        self.cache_id = address..(port or "0")..(family or "0")
        local addr = iostream._dns_cache[self.cache_id]
        if addr then
            return unpack(addr)
        end
        -- Set max time for DNS to resolve.
        self.com_port = "/tmp/turbo-dns-"..tostring(math.random(0,0xffffff))
        self:_lookup_name(address, port, family)
        self.ctx = coctx.CoroutineContext(self.io_loop)
        local _self = self
        self._dns_timeout = self.io_loop:add_timeout(
            util.gettimemonotonic() + ((self.args.dns_timeout or
                    30)*1000), function()
                if _self.pid then
                    ffi.C.kill(_self.pid, signal.SIGKILL)
                    ffi.C.wait(nil)
                    _self.pid = nil
                end
                ffi.C.close(_self.server_sockfd)
                os.remove(_self.com_port)
                _self.ctx:set_arguments("DNS resolv timeout.")
                _self.ctx:finalize_context()
            end
        )
        local err, servinfo, sockaddr = coroutine.yield(self.ctx)
        if err then
            error(err)
        end
        return servinfo, sockaddr
    end

    function iostream.DNSResolv:clean()
        iostream._dns_cache = iostream.DNSCache()
    end

    ffi.cdef [[
        struct __packed_addrinfo{
            int ai_flags;
            int ai_family;
            int ai_socktype;
            int ai_protocol;
            socklen_t ai_addrlen;
            struct sockaddr ai_addr;
        }
    ]]

    local function _pack_addrinfo(addrinfo)
        local packed = ffi.new("struct __packed_addrinfo")
        packed.ai_flags = addrinfo.ai_flags
        packed.ai_family = addrinfo.ai_family
        packed.ai_socktype = addrinfo.ai_socktype
        packed.ai_protocol = addrinfo.ai_protocol
        packed.ai_addrlen = addrinfo.ai_addrlen
        packed.ai_addr.sa_family = addrinfo.ai_addr.sa_family
        ffi.copy(packed.ai_addr.sa_data,
                 addrinfo.ai_addr.sa_data,
                 ffi.sizeof(addrinfo.ai_addr.sa_data))
        return ffi.string(ffi.cast("unsigned char*", packed),
                          ffi.sizeof(packed))
    end

    local function _unpack_addrinfo(packed)
        local addrinfo = ffi.new("struct addrinfo")
        local sockaddr = ffi.new("struct sockaddr")
        addrinfo.ai_addr = sockaddr
        local _packed = ffi.new("struct __packed_addrinfo")
        ffi.copy(_packed,
                 ffi.cast("unsigned char*", packed),
                 ffi.sizeof(_packed))
        addrinfo.ai_flags = _packed.ai_flags
        addrinfo.ai_family = _packed.ai_family
        addrinfo.ai_socktype = _packed.ai_socktype
        addrinfo.ai_protocol = _packed.ai_protocol
        addrinfo.ai_addrlen = _packed.ai_addrlen
        addrinfo.ai_addr.sa_family = _packed.ai_addr.sa_family
        ffi.copy(addrinfo.ai_addr.sa_data, _packed.ai_addr.sa_data,
                 ffi.sizeof(addrinfo.ai_addr.sa_data))
        addrinfo.ai_canonname = nil
        addrinfo.ai_next = nil
        -- Return all to avoid losing reference and gc cleaning up the pointers.
        return addrinfo, sockaddr
    end

    function iostream.DNSResolv:_send_resolv_result(servport,
                                                   success,
                                                   errdesc,
                                                   addrinfo)
        local errno, rc
        local client_address = ffi.new("struct sockaddr_un");

        client_address.sun_family = socket.AF_UNIX;
        ffi.copy(client_address.sun_path, 
            ffi.cast("const char*", self.com_port),
            math.min(self.com_port:len(), ffi.sizeof(client_address.sun_path)))
        self.client_sockfd = ffi.C.socket(socket.AF_UNIX, socket.SOCK_STREAM, 0);
        if self.client_sockfd < 0 then
            errno = ffi.errno()
            log.error(string.format(
                "[iostream.lua] Errno %d. Could not create Unix socket FD for DNS resolv. %s",
                errno,
                socket.strerror(errno)))
            os.exit(1)
        end
        rc = ffi.C.connect(self.client_sockfd,
                           ffi.cast("const struct sockaddr *", client_address),
                           ffi.sizeof(client_address))
        if rc ~= 0 then
            -- Main thread probably has not created socket yet. Wait.
            -- Should be done more elegantly...
            ffi.C.sleep(1)
            rc = ffi.C.connect(self.client_sockfd,
                               ffi.cast("const struct sockaddr *", client_address),
                               ffi.sizeof(client_address))
        end
        if rc ~= 0 then
            errno = ffi.errno()
            log.error(string.format(
                "[iostream.lua] Errno %d. Could not connect to main thread pipe. %s",
                errno,
                socket.strerror(errno)))
            ffi.C.close(self.client_sockfd)
            os.exit(1)
        end
        local res = (success and "0" or "1")..
                    "\r\n\r\n"..
                    errdesc..
                    "\r\n\r\n"..
                    (addrinfo and _pack_addrinfo(addrinfo[0]) or "")..
                    "\r\n\r\n"
        rc = ffi.C.send(self.client_sockfd, ffi.cast("const char*", res), res:len(), 0)
        ffi.C.close(self.client_sockfd)
        if rc == -1 then
            log.error(
                "[iostream.lua] Could not send data to DNS resolv recipient server.")
        end
        os.exit(1)
    end

    function iostream.DNSResolv:_lookup_name(address, port, family)
        -- Async DNS.
        local servport = math.random(10000,20000)
        local pid = ffi.C.fork()
        if pid < 0 then
            error("Could not create thread for DNS resolver.")
        end
        if pid ~= 0 then
            local errno, rc, msg
            self.pid = pid
            local server_address = ffi.new("struct sockaddr_un");
            server_address.sun_family = socket.AF_UNIX;
            ffi.copy(server_address.sun_path, 
                ffi.cast("const char*", self.com_port),
                math.min(self.com_port:len(), ffi.sizeof(server_address.sun_path)))
            self.server_sockfd = ffi.C.socket(socket.AF_UNIX, socket.SOCK_STREAM, 0);
            if self.server_sockfd < 0 then
                error("Could not create Unix socket FD")
            end
            rc, msg = socket.set_nonblock_flag(self.server_sockfd)
            if rc ~= 0 then
               error(msg)
            end

            if ffi.C.bind(self.server_sockfd,
                       ffi.cast("struct sockaddr*", server_address),
                       ffi.sizeof(server_address)) ~= 0 then
                errno = ffi.errno()
                error(string.format(
                    "Errno %d. Could not bind to address. %s",
                    errno,
                    socket.strerror(errno)))
            end
            if ffi.C.listen(self.server_sockfd, 1) ~= 0 then
                errno = ffi.errno()
                error(string.format(
                    "Errno %d. Could not listen to socket fd %d. %s",
                    errno,
                    fd,
                    socket.strerror(errno)))
            end
            sockutil.add_accept_handler(self.server_sockfd,
                                        iostream.DNSResolv._dns_resolved_callback,
                                        self.io_loop,
                                        self)
            return
        end
        -- Fork will continue here.
        local hints = ffi.new("struct addrinfo[1]")
        local servinfo = ffi.new("struct addrinfo *[1]")
        local rc

        self.address = address
        self.port = port
        ffi.fill(hints[0], ffi.sizeof(hints[0]))
        hints[0].ai_socktype = SOCK_STREAM
        hints[0].ai_family = family or AF_UNSPEC
        hints[0].ai_protocol = 0
        rc = ffi.C.getaddrinfo(address, tostring(port), hints, servinfo)
        if rc ~= 0 then
            if rc == -EAI_AGAIN then
                ffi.C.__res_init()
            end
            local strerr = ffi.string(C.gai_strerror(rc))
            local errdesc = string.format(
                "Could not resolve hostname '%s': %s",
                address, ffi.string(C.gai_strerror(rc)))
            self:_send_resolv_result(servport, false, errdesc, nil)
            os.exit(0)
        end
        self:_send_resolv_result(servport, true, "OK", servinfo)
        os.exit(0)
    end

    function iostream.DNSResolv:_dns_resolved_callback(fd, peername)
        local _self = self
        local pipe = iostream.IOStream(fd, self.io_loop)
        pipe:read_until_pattern("\r\n\r\n", function(rc)
            pipe:read_until_pattern("\r\n\r\n", function(errmsg)
                if tonumber(rc) ~= 0 then
                    pipe:close()
                    ffi.C.wait(nil) -- Join.                    
                    ffi.C.close(self.server_sockfd)
                    _self.server_sockfd = nil
                    _self.io_loop:remove_timeout(self._dns_timeout)
                    os.remove(self.com_port)

                    _self.ctx:set_arguments(errmsg)
                    _self.ctx:finalize_context()
                    return
                end
                pipe:read_until_pattern("\r\n\r\n", function(packed_servinfo)
                    pipe:close()
                    ffi.C.wait(nil) -- Join.                    
                    ffi.C.close(self.server_sockfd)
                    self.server_sockfd = nil
                    self.io_loop:remove_timeout(self._dns_timeout)
                    os.remove(self.com_port)
                    local servinfo, sockaddr =
                        _unpack_addrinfo(packed_servinfo)
                    iostream._dns_cache[self.cache_id] = {servinfo, sockaddr}
                    _self.ctx:set_arguments({false, servinfo, sockaddr})
                    _self.ctx:finalize_context()
                end)
            end)
        end)
    end
end

return iostream
