--- Turbo.lua Thread module
--
-- Copyright 2016 John Abrahamsen
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

local ffi = require "ffi"
local ioloop = require "turbo.ioloop"
local util = require "turbo.util"
local log = require "turbo.log"
local socket = require "turbo.socket_ffi"
local sockutil = require "turbo.sockutil"
local iostream = require "turbo.iostream"
local coctx = require "turbo.coctx"
require "turbo.cdef"

local thread = {}

thread.Thread = class("Thread")

--- The Thread class is implemented with C fork, and allows the user to create 
-- a seperate thread that runs independently of the main thread, but can
-- communicate with each other over a AF_UNIX socket. Useful for long and heavy
-- tasks that can not be yielded. Also useful for running shell commands etc.
-- Usage:
--     turbo.ioloop.instance():add_callback(function()
--         local thread = turbo.thread.Thread(function(th)
--             th:send("Hello World.")
--             th:stop()
--         end)
--
--         print(thread:wait_for_data())
--         thread:wait_for_finish()
--         turbo.ioloop.instance():close()
--     end):start()
-- All functions are yielded to the IOLoop internally.
-- @param func Function to call when thread has been created. Function is called
-- with the childs Thread object, which contains its own IOLoop
-- e.g: "th.io_loop".
function thread.Thread:initialize(func, args)
    --self.args = args or {}
    self.io_loop = io_loop or ioloop.instance()
    self.running = true
    self._child_func = func
    return self:_run_thread()
end

-- Stop thread and cleanup pipe.
function thread.Thread:stop()
    if self.main_thread then
        -- Send stop message over wire.
        self.pipe:write("STOP\r\n\r\n", function()
            ffi.C.wait(nil)
        end)
    else
        -- Stop thread as child.
        local _self = self
        self.pipe:write("STOP\r\n\r\n", function()
                _self.pipe:close()
                _self.io_loop:close()
                os.remove(self.com_port)
                os.exit(0)
            end
        )
    end
end

--- Called by either main or child thread to send data to each other.
-- @param data (String) String to be sent.
function thread.Thread:send(data)
    self.pipe:write("DATA\r\n\r\n"..data:len().."\r\n\r\n"..data)
end

--- Wait for data to become available on communication socket.
function thread.Thread:wait_for_data()
    self.data_ctx = coctx.CoroutineContext(self.io_loop)
    if self._waiting_data then
        -- Data is already available.
        local data = self._waiting_data
        self._waiting_data = nil
        return data
    end
    local err, data = coroutine.yield(self.data_ctx)
    if err then
        error(err)
    end
    return data
end

--- Wait for thread to stop running.
-- Only callable from main thread.
function thread.Thread:wait_for_finish()
    if not self.main_thread then
        error("Child thread can not wait for child thread.")
    end
    if not self.running then
        return
    end
    self.fin_ctx = coctx.CoroutineContext(self.io_loop)
    local err = coroutine.yield(self.fin_ctx)
    if err then
        error(err)
    end
end

--- Wait for thread pipe to be connected. Must be used by main thread
-- before attempting to send data to child.
-- Only callable from main thread.
function thread.Thread:wait_for_pipe()
    if not self.main_thread then
        error(
            "Child thread does not need to wait for pipe.")
    end
    if self.connected then
        return
    end
    self.connect_ctx = coctx.CoroutineContext(self.io_loop)
    local err = coroutine.yield(self.connect_ctx)
    if err then
        error(err)
    end
end

--- Get PID of child.
-- @return (Number) PID
function thread.Thread:get_pid()
    if not self.main_thread then
        return tonumber(ffi.C.getpid())
    end
    return self.running_pid
end

function thread.Thread:_run_thread()
    self.com_port = "/tmp/turbo-com" .. tostring(math.random(1, 9999999))
    local pid = ffi.C.fork()
    if pid < 0 then
        error("Could not create child thread.")
    end
    if pid ~= 0 then
        -- Main thread continue.
        self.main_thread = true
        self.running = true
        self.running_pid = pid
        self:_create_unix_sock()
        return
    end
    -- New thread.
    self.io_loop = ioloop.IOLoop()
    _G.io_loop_instance = self.io_loop
    self.main_thread = false
    self:_connect_to_main_thread()
end

function thread.Thread:_restore_coctx_with_error(err)
    if self.data_ctx then
        local ctx = self.data_ctx
        self.data_ctx = nil
        ctx:set_arguments(err)
        ctx:finalize_context()
        return
    end
    if self.pipe_ctx then
        local ctx = self.pipe_ctx
        self.pipe_ctx = nil
        ctx:set_arguments(err)
        ctx:finalize_context()
        return
    end
    if self.fin_ctx then
        local ctx = self.fin_ctx
        self.fin_ctx = nil
        ctx:set_arguments(err)
        ctx:finalize_context()
        return
    end
end

function thread.Thread:_execute_thread_func()
    local _self = self
    xpcall(self._child_func, function(err) 
        -- Child thread encountered error.
        -- Cleanup everything and exit thread.
        local thread = tonumber(ffi.C.getpid())
        local trace = debug.traceback(coroutine.running(), err, 2):gsub(
            "stack traceback:", "thread traceback")
        local _str_borders_down = string.rep("/", 80)
        local _str_borders_up = string.rep("\\", 80)
        local err =
            string.format(
            "Error in thread. PID %s is dead.\n%s\n%s\n%s",
            thread,
            _str_borders_down,
            trace,
            _str_borders_up)

        _self.pipe:write("ERRO\r\n\r\n"..err:len().."\r\n\r\n"..err, function()
            _self:stop()
        end)
    end,
    self)
end

function thread.Thread:_connect_to_main_thread()
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
            "[thread.lua ]Errno %d. Could not create Unix socket FD. %s",
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
            "[thread.lua] Errno %d. Could not connect to main thread pipe. %s",
            errno,
            socket.strerror(errno)))
        ffi.C.close(self.client_sockfd)
        os.exit(1)
    end
    self.pipe = iostream.IOStream(self.client_sockfd, self.io_loop)
    self.pipe:read_until("\r\n\r\n",
                                 thread.Thread._main_command_sent,
                                 self)
    self.ready_to_send = true
    self.io_loop:add_callback(thread.Thread._execute_thread_func, self)
    -- Child thread will block here and prevent it from using the other
    -- IOLoop that is in shared memory.
    self.io_loop:start()
end

function thread.Thread:_create_unix_sock()
    local errno, rc, msg

    if not self.main_thread then
        error("Can not open Unix socket on child.")
    end
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
                                 thread.Thread._child_connects,
                                 self.io_loop,
                                 self)
    self.ready_to_send = true
end

--- Called when child thread connects to main thread.
function thread.Thread:_child_connects(fd)
    local pipe = iostream.IOStream(fd, self.io_loop)
    local _self = self
    self.pipe = pipe
    self.connected = true
    pipe:read_until("\r\n\r\n",
                    thread.Thread._child_command_sent,
                    self)
    if self.connect_ctx then
        local ctx = self.connect_ctx
        self.connect_ctx = nil
        ctx:finalize_context()
    end
end

--- Called when child thread is sending data over pipe.
function thread.Thread:_data_sent(data)
    -- Continue listening for next command.
    self.pipe:read_until("\r\n\r\n",
                         thread.Thread._child_command_sent,
                         self)
    if self.data_ctx then
        local ctx = self.data_ctx
        self.data_ctx = nil
        ctx:set_arguments({false, data})
        ctx:finalize_context()
    else
        -- No one is waiting for data... Store recieved data until
        -- it can be consumed or discarded.
        self._waiting_data = data
    end
end

--- Called when child thread is sending data over pipe.
function thread.Thread:_child_command_sent(cmd)
    local _self = self
    cmd = cmd:sub(1,4) -- Shave off CRLF
    if cmd == "DATA" then
        self.pipe:read_until("\r\n\r\n", function(num_bytes)
            _self.pipe:read_bytes(tonumber(num_bytes),
                                  thread.Thread._data_sent,
                                  _self)
        end)
    elseif cmd == "STOP" then
        _self.pipe:close()
        ffi.C.close(_self.server_sockfd)
        self.running = false
        -- Collect thread.
        ffi.C.wait(nil)
        if self.fin_ctx then
            local ctx = self.fin_ctx
            self.fin_ctx = nil
            ctx:finalize_context()
        end
    elseif cmd == "ERRO" then
        self.pipe:read_until("\r\n\r\n", function(num_bytes)
            _self.pipe:read_bytes(tonumber(num_bytes),
                                  thread.Thread._restore_coctx_with_error,
                                  _self)
        end)
    end
end

--- Called when main thread is sending data over pipe.
function thread.Thread:_main_command_sent(cmd)
    local _self = self
    cmd = cmd:sub(1,4) -- Shave off CRLF
    if cmd == "DATA" then
        self.pipe:read_until("\r\n\r\n", function(num_bytes)
            _self.pipe:read_bytes(tonumber(num_bytes),
                                  thread.Thread._data_sent,
                                  _self)
        end)
    elseif cmd == "STOP" then
        self.pipe:close()
        self.io_loop:close()
        os.exit(0)
    end
end

return thread
