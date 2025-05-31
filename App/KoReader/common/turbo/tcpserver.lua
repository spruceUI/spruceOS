--- Turbo.lua TCP Server module
-- A simple non-blocking extensible TCP Server based on the IOStream class.
-- Includes SSL support. Used as base for the Turbo HTTP Server.
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

local log =         require "turbo.log"
local util =        require "turbo.util"
local iostream =    require "turbo.iostream"
local platform =    require "turbo.platform"
local ioloop =      require "turbo.ioloop"
local socket =      require "turbo.socket_ffi"
local sockutil =    require "turbo.sockutil"
local crypto =      require "turbo.crypto"
local platform =    require "turbo.platform"
local ffi =         require "ffi"
local bit =         jit and require "bit" or require "bit32"
require "turbo.cdef"
require "turbo.3rdparty.middleclass"

local C = ffi.C

local tcpserver = {}  -- tcpserver namespace

--- A non-blocking TCP server class.
-- Users which want to create a TCP server should inherit from this class and
-- implement the TCPServer:handle_stream() method.
-- SSL is supported by providing the ssl_options table on class initialization.
tcpserver.TCPServer = class('TCPServer')

--- Create a new TCPServer class instance.
-- @param io_loop (IOLoop instance)
-- @param ssl_options (Table) Optional SSL parameters.
-- @param max_buffer_size (Number) The maximum buffer size of the server. If
-- the limit is hit, the connection is closed.
-- @note If the SSL certificates can not be loaded, a error is raised.
function tcpserver.TCPServer:initialize(io_loop, ssl_options, max_buffer_size)
    self.io_loop = io_loop
    self.ssl_options = ssl_options
    self.max_buffer_size = max_buffer_size
    self._sockets = {}
    self._pending_sockets = {}
    self._started = false
    -- Validate SSL options if set.
    if self.ssl_options then
        if not type(ssl_options.cert_file) == "string" then
            error("ssl_options argument is set, but cert_file argument is \
                missing or not a string.")
        end
        if not type(ssl_options.key_file) == "string" then
            error("ssl_options argument is set, but key_file arguments is \
                missing or not a string.")
        end
        -- So the only check that is done is that the cert and key file are
        -- readable. However the validity of the keys are not checked until
        -- we create the SSL context.
        if not util.file_exists(ssl_options.cert_file) then
            error(string.format("SSL cert_file, %s, does not exist.",
                ssl_options.cert_file))
        end
        if not util.file_exists(ssl_options.key_file) then
            error(string.format("SSL key_file, %s, does not exist.",
                ssl_options.key_file))
        end
        -- The ssl_create_context function will raise error and exit by its
        -- own, so there is no need to catch errors.
        local rc, ctx_or_err = crypto.ssl_create_server_context(
            self.ssl_options.cert_file, self.ssl_options.key_file, self.ssl_options.ca_path)
        if rc ~= 0 then
            error(string.format("Could not create SSL context. %s",
                ctx_or_err))
        end
        self._ssl_ctx = ctx_or_err
        self.ssl_options._ssl_ctx = self._ssl_ctx
    end
end

--- Implement this method to handle new connections.
-- @param stream (IOStream instance) Stream for the newly connected client.
-- @param address (String) IP address of newly connected client.
function tcpserver.TCPServer:handle_stream(stream, address)
    error('handle_stream method not implemented in this object')
end

--- Start listening on port and address.
-- When using this method, as oposed to TCPServer:bind you should not call
-- TCPServer:start. You can call this method multiple times with different
-- parameters to bind multiple sockets to the same TCPServer.
-- @param port (Number) The port number to bind to.
-- @param address (Number) The address to bind to in unsigned integer hostlong
-- format. If not address is given, INADDR_ANY will be used, binding to all
-- addresses.
-- @param backlog (Number) Maximum backlogged client connects to allow. If not
-- defined then 128 is used as default.
-- @param family (Number) Optional socket family. Defined in Socket module. If
-- not defined AF_INET is used as default.
function tcpserver.TCPServer:listen(port, address, backlog, family)
    assert(port, [[Please specify port for listen() method]])
    local sock = sockutil.bind_sockets(port, address, backlog, family)
    self:add_sockets({sock})
end

--- Add multiple sockets in a table that should be bound on calling start.
-- @param sockets (Table) 1 or more socket fd's.
-- @note Use the sockutil.bind_sockets function to create sockets easily and
-- add them to the sockets table.
function tcpserver.TCPServer:add_sockets(sockets)
    if not self.io_loop then
        self.io_loop = ioloop.instance()
    end
    for _, sock in ipairs(sockets) do
        self._sockets[#self._sockets + 1] = sock
        sockutil.add_accept_handler(sock,
            self._handle_connection,
            self.io_loop,
            self)
    end
end

--- Add a single socket that should be bound on calling start.
-- @param socket (Number) Socket fd.
-- @note Use the sockutil.bind_sockets to create sockets easily and add them to
-- the sockets table.
function tcpserver.TCPServer:add_socket(socket) self:add_sockets({socket}) end

--- Bind this server to port and address.
-- @note No sockets are bound until TCPServer:start is called.
-- @param port (Number) The port number to bind to.
-- @param address (Number) The address to bind to in unsigned integer hostlong
-- format. If not address is given, INADDR_ANY will be used, binding to all
-- addresses.
-- @param backlog (Number) Maximum backlogged client connects to allow. If not
-- defined then 128 is used as default.
-- @param family (Number) Optional socket family. Defined in Socket module. If
-- not defined AF_INET is used as default.
function tcpserver.TCPServer:bind(port, address, backlog, family)
    local sockets = sockutil.bind_sockets(port, address, backlog, family)
    if self._started then
       self:add_sockets(sockets)
    else
       self._pending_sockets[#self._pending_sockets + 1] = sockets
    end
end

--- Start the TCPServer.
function tcpserver.TCPServer:start(procs)
    assert((not self._started), "Already started TCPServer.")
    self._started = true
    if procs and procs > 1 and platform.__LINUX__ then
        for _ = 1, procs - 1 do
            local pid = ffi.C.fork()
            if pid ~= 0 then
                log.devel(string.format(
                    "[tcpserver.lua] Created extra worker process: %d",
                    tonumber(pid)))
                break
            end
        end
    end
    local sockets = self._pending_sockets
    self._pending_sockets = {}
    self:add_sockets(sockets)
end

--- Stop the TCPServer.
function tcpserver.TCPServer:stop()
    for _, fd in ipairs(self._sockets) do
       self.io_loop:remove_handler(fd)
       self:_close(fd)
    end
    self._sockets = {}
end

if platform.__LINUX__ and not _G.__TURBO_USE_LUASOCKET__ then
    function tcpserver.TCPServer:_close(fd)
        assert(C.close(fd) == 0, "Failed to close socket.")
    end
else
    function tcpserver.TCPServer:_close(fd)
        assert(fd:close())
    end
end


--- Internal function for wrapping new raw sockets in a IOStream class instance.
-- @param connection (Number) Client socket fd.
-- @param address (String) IP address of newly connected client.
function tcpserver.TCPServer:_handle_connection(connection, address)
    if self.ssl_options ~= nil then
        local stream = iostream.SSLIOStream(
            connection,
            self.ssl_options,
            self.io_loop,
            self.max_buffer_size)
        self:handle_stream(stream, address)
    else
        local stream = iostream.IOStream(
            connection,
            self.io_loop,
            self.max_buffer_size)
        self:handle_stream(stream, address)
    end
end

return tcpserver
