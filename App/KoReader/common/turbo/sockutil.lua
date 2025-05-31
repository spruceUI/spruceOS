--- Turbo.lua Socket Utils
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

local socket =      require "turbo.socket_ffi"
local ioloop =      require "turbo.ioloop"
local log =         require "turbo.log"
local ffi =         require "ffi"
local bit =         jit and require "bit" or require "bit32"
local platform =    require "turbo.platform"
local luasocket
if not platform.__LINUX__ or _G.__TURBO_USE_LUASOCKET__ then
    luasocket = require "socket"
end

local C = ffi.C

local sockutils = {} -- sockutils namespace
local _add_accept_hander_cb

if platform.__LINUX__ and not _G.__TURBO_USE_LUASOCKET__ then
    local SOL_SOCKET =  socket.SOL_SOCKET
    local SO_RESUSEADDR = socket.SO_REUSEADDR
    local O_NONBLOCK =  socket.O_NONBLOCK
    local F_SETFL =     socket.F_SETFL
    local F_GETFL =     socket.F_GETFL
    local SOCK_STREAM = socket.SOCK_STREAM
    local INADDRY_ANY = socket.INADDR_ANY
    local AF_INET =     socket.AF_INET
    local AF_INET6 =    socket.AF_INET6
    local EINPROGRESS = socket.EINPROGRESS
    local EWOULDBLOCK = socket.EWOULDBLOCK
    local EAGAIN =      socket.EAGAIN
    local INET_ADDRSTRLEN = 16
    local INET6_ADDRSTRLEN = 46

    --- Creates the sockaddr_in or sockaddr_in6 struct
    -- If not address is defined '0.0.0.0'/'::' will be used.
    -- If not family is defined then AF_INET(ipv4) will be used
    -- @param address (Number or String) The address to bind to in unsigned
    -- integer hostlong or a string like "127.0.0.1".
    -- If not address is given, INADDR_ANY or ("::" for ipv6) will be used,
    -- binding to all addresses.
    -- @param port (Number) The port number to bind to.
    -- @param family (Number) Optional socket family. Defined in Socket module. If
    -- not defined AF_INET is used as default.
    function sockutils.create_server_address(port, address, family)
        local serv_addr
        local rc
        local errno

        family = family or AF_INET

        if family ~= AF_INET and family ~= AF_INET6 then
            error("[sockutil.lua] Only AF_INET and AF_INET6 is supported")
        end

        if family == AF_INET then
            address = address or "0.0.0.0"
            serv_addr = ffi.new("struct sockaddr_in")
            serv_addr.sin_family = AF_INET
            serv_addr.sin_port = C.htons(port)
        else
            address = address or "::"
            serv_addr = ffi.new("struct sockaddr_in6")
            serv_addr.sin6_family = family
            serv_addr.sin6_port = C.htons(port)
        end

        if type(address) == "string" then
            rc = ffi.C.inet_pton(family, address,
                family == AF_INET and serv_addr.sin_addr or serv_addr.sin6_addr)
            if rc == 0 then
                error(string.format("[sockutil.lua] Invalid address %s",
                    address))
            elseif rc == -1 then
                errno = ffi.errno()
                error(string.format(
                    "[sockutil.lua Errno %d] Could not parse address. %s",
                    errno,
                    socket.strerror(errno)))
            end
        elseif type(address) == "number" and family == AF_INET then
            if family == AF_INET then
                serv_addr.sin_addr.s_addr = C.htonl(address);
            end
        else
            error("[sockutil.lua] Invalid input address must be a valid \
                    ipv4(string/int) or ipv6(string) address.")
        end

        return serv_addr
    end

    --- Connect to a remote host using an addrinfo struct
    -- Returns the addrinfo struct that was used on success, or nil and
    -- an error message on failure.
    -- @param sock A socket descriptor
    -- @param ai a struct addrinfo
    function sockutils.connect_addrinfo(sock, p)
        local r = 0
        local errno = 0
        if p == nil then
            return nil, "Could not connect, addrinfo is NULL."
        end
        r = C.connect(sock, p.ai_addr, p.ai_addrlen)
        if r ~= 0 then
            errno = ffi.errno()
            if errno == EINPROGRESS then
                return p
            end
            return nil,
                string.format("Could not connect. Errno %d: %s",
                    errno, socket.strerror(errno) or "")
        end
        return p
    end


    --- Binds sockets to port and address.
    -- If not address is defined then * will be used.
    -- If no backlog size is given then 128 connections will be used.
    -- @param address (Number or String) The address to bind to in unsigned
    -- integer hostlong or a string like "127.0.0.1".
    -- If not address is given, INADDR_ANY or ("::" for ipv6) will be used,
    -- binding to all addresses.
    -- @param port (Number) The port number to bind to.
    -- @param backlog (Number) Maximum backlogged client connects to allow. If not
    -- defined then 128 is used as default.
    -- @param family (Number) Optional socket family. Defined in Socket module. If
    -- not defined AF_INET is used as default.
    function sockutils.bind_sockets(port, address, backlog, family)
        local serv_addr
        local errno
        local rc, msg

        backlog = backlog or 128

        if not family then
            if type(address) == "string" then
                if address:find(":") then
                    family = AF_INET6
                else
                    family = AF_INET
                end
            else
                family = AF_INET
            end
        end

        serv_addr = sockutils.create_server_address(port, address, family)

        local fd = C.socket(family, SOCK_STREAM, 0)
        if fd == -1 then
            errno = ffi.errno()
            error(string.format(
                "[tcpserver.lua Errno %d] Could not create socket. %s",
                errno,
                socket.strerror(errno)))
        end
        rc, msg = socket.set_nonblock_flag(fd)
        if rc ~= 0 then
           error("[tcpserver.lua] " .. msg)
        end
        rc, msg = socket.set_reuseaddr_opt(fd)
        if rc ~= 0 then
           error("[tcpserver.lua] " .. msg)
        end
        if C.bind(fd, ffi.cast("struct sockaddr *", serv_addr),
            ffi.sizeof(serv_addr)) ~= 0 then
            errno = ffi.errno()
            error(string.format(
                "[tcpserver.lua Errno %d] Could not bind to address. %s",
                errno,
                socket.strerror(errno)))
        end
        if C.listen(fd, backlog) ~= 0 then
            errno = ffi.errno()
            error(string.format(
                "[tcpserver.lua Errno %d] Could not listen to socket fd %d. %s",
                errno,
                fd,
                socket.strerror(errno)))
        end
        --log.devel(string.format("[tcpserver.lua] Listening to socket fd %d", fd))
        return fd
    end

    local client_addr = ffi.new("struct sockaddr_storage")
    local client_addr_sz = ffi.new("int32_t[1]", ffi.sizeof(client_addr))

    _add_accept_hander_cb = function(arg, fd, events)
       while true do
            local errno
            local address
            --log.devel(string.format(
                --"[tcpserver.lua] Accepting connection on socket fd %d", fd))

            local client_fd =
                C.accept(fd, ffi.cast("struct sockaddr *", client_addr),
                         client_addr_sz)
            local family = client_addr.ss_family
            if client_fd == -1 then
                errno = ffi.errno()
                if (errno == EWOULDBLOCK or errno == EAGAIN) then
                    break
                else
                    log.error(string.format(
                        "[tcpserver.lua Errno %d] Could not accept connection. %s",
                        errno,
                        socket.strerror(errno)))
                    break
                end
            end

            if family == AF_INET then
                local sockaddr_in = ffi.cast("struct sockaddr_in *", client_addr)
                local s_addr_ptr = ffi.cast("unsigned char *", sockaddr_in.sin_addr)
                address = string.format("%d.%d.%d.%d",
                      s_addr_ptr[0],
                      s_addr_ptr[1],
                      s_addr_ptr[2],
                      s_addr_ptr[3])
            else
                local client_sa = ffi.cast("struct sockaddr_in6 *", client_addr)
                local addrbuf = ffi.new("char[?]", INET6_ADDRSTRLEN)
                C.inet_ntop(AF_INET6, client_sa.sin6_addr, addrbuf, INET6_ADDRSTRLEN)
                address = ffi.string(addrbuf, INET6_ADDRSTRLEN)
            end

            if arg[2] then
                arg[1](arg[2], client_fd, address)
            else
                arg[1](client_fd, address)
            end
        end
    end
else
    -- LuaSocket version.
    function sockutils.bind_sockets(port, address, backlog, family)
        local sock = luasocket.bind(address or "127.0.0.1", port, backlog)
        sock:settimeout(0)
        return sock
    end

    _add_accept_hander_cb = function(arg, fd, events)
        while true do
            local client_fd = fd:accept()
            if not client_fd then
                break
            end
            client_fd:settimeout(0)
            client_fd:setoption("keepalive", true)
            if arg[2] then
                arg[1](arg[2], client_fd, client_fd:getpeername())
            else
                arg[1](client_fd, client_fd:getpeername())
            end
        end
    end
end


--- Add accept handler for socket with given callback.
-- Either supply a IOLoop object, or the global instance will be used...
-- @param sock (Number) Socket file descriptor to add handler for.
-- @param callback (Function) Callback to handle connects. Function receives
-- socket fd (Number) and address (String) of client as parameters.
-- @param io_loop (IOLoop instance) If not set the global is used.
-- @param arg Optional argument for callback.
function sockutils.add_accept_handler(sock, callback, io_loop, arg)
    local io_loop = io_loop or ioloop.instance()
    io_loop:add_handler(
        sock,
        ioloop.READ,
        _add_accept_hander_cb,
        {callback, arg})
end

return sockutils