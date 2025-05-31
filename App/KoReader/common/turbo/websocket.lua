--- Turbo.lua Websocket module.
--
-- Websockets according to the RFC 6455. http://tools.ietf.org/html/rfc6455
--
-- The module offers two classes:
-- * WebSocketHandler - WebSocket support for turbo.web.Application.
-- * WebSocketClient  - Callback based WebSocket client.
-- Both classes uses the mixin class WebSocketStream, which in turn provides
-- almost identical API's for the two classes once connected. Both classes
-- support SSL (wss://).
--
-- NOTICE: _G.TURBO_SSL MUST be set to true and OpenSSL or axTLS MUST be
-- installed to use this module.
--
-- Copyright 2013 John Abrahamsen
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

local math =            require "math"
local bit =             jit and require "bit" or require "bit32"
local ffi =             require "ffi"
local log =             require "turbo.log"
local httputil =        require "turbo.httputil"
local httpserver =      require "turbo.httpserver"
local buffer =          require "turbo.structs.buffer"
local escape =          require "turbo.escape"
local util =            require "turbo.util"
local hash =            require "turbo.hash"
local platform =        require "turbo.platform"
local web =             require "turbo.web"
local async =           require "turbo.async"
local buffer =          require "turbo.structs.buffer"
require('turbo.3rdparty.middleclass')
local libturbo_parser = util.load_libtffi()
local le = ffi.abi("le")
local be = not le
local strf = string.format
local bor = bit.bor
math.randomseed(util.gettimeofday())

local ENDIAN_SWAP_U64
if jit and jit.version_num >= 20100 then
    ENDIAN_SWAP_U64 = function(val)
        return bit.bswap(val)
    end
else
    -- Only LuaJIT v2.1 support 64bit bit swap.
    -- Use a native C function instead for v2.0.
    ENDIAN_SWAP_U64 = function(val)
        return libturbo_parser.turbo_bswap_u64(val)
    end
end

ffi.cdef [[
    struct ws_header {
        uint8_t flags;
        uint8_t len;
        union {
            uint16_t sh;
            uint64_t ll;
        } ext_len;
    } __attribute__ ((__packed__));
]]

local _ws_header = ffi.new("struct ws_header")
local _ws_mask = ffi.new("int32_t[1]")

local _unmask_payload
if platform.__WINDOWS__ then
    _unmask_payload = function(mask32, data)
        local i = ffi.new("size_t", 0)
        local sz = data:len()
        local buf = ffi.cast("char*", ffi.C.malloc(data:len()))
        if buf == nil then
            error("Could not allocate memory for WebSocket frame masking.\
                  Catastrophic failure.")
        end
        data = ffi.cast("char*", data)
        local mask = ffi.cast("char*", mask32)
        while i < sz do
            buf[i] = bit.bxor(data[i],  mask[i % 4])
            i = i + 1
        end
        local str = ffi.string(buf, sz)
        ffi.C.free(buf)
        return str
    end
else
    _unmask_payload = function(mask, data)
        local ptr = libturbo_parser.turbo_websocket_mask(mask, data, data:len())
        if ptr ~= nil then
            local str = ffi.string(ptr, data:len())
            ffi.C.free(ptr)
            return str
        else
            error("Could not allocate memory for WebSocket frame masking.\
                  Catastrophic failure.")
        end
    end
end

local websocket = {}

websocket.MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

--- Websocket opcodes.
websocket.opcode = {
    CONTINUE =  0x0,
    TEXT =      0x1,
    BINARY =    0x2,
    -- 0x3-7 Reserved
    CLOSE =     0x8,
    PING =      0x9,
    PONG =      0xA,
    -- 0xB-F Reserved
}

websocket.errors = {
     INVALID_URL = -1 -- URL could not be parsed.
    ,INVALID_SCHEMA = -2 -- Invalid URL schema
    ,COULD_NOT_CONNECT = -3 -- Could not connect, check message.
    ,PARSE_ERROR_HEADERS = -4 -- Could not parse response headers.
    ,CONNECT_TIMEOUT = -5 -- Connect timed out.
    ,REQUEST_TIMEOUT = -6 -- Request timed out.
    ,NO_HEADERS = -7 -- Shouldnt happen.
    ,REQUIRES_BODY = -8 -- Expected a HTTP body, but none set.
    ,INVALID_BODY = -9 -- Request body is not a string.
    ,SOCKET_ERROR = -10 -- Socket error, check message.
    ,SSL_ERROR = -11 -- SSL error, check message.
    ,BUSY = -12 -- Operation in progress.
    ,REDIRECT_MAX = -13 -- Redirect maximum reached.
    ,CALLBACK_ERROR = -14 -- Error in callback.
    ,BAD_HTTP_STATUS = -15
    ,WEBSOCKET_PROTOCOL_ERROR = -16
}

--- WebSocketStream is a abstraction for a WebSocket connection,
-- used as class mixin in WebSocketHandler and WebSocketClient.
websocket.WebSocketStream = {}

--- Send a message to the client of the active Websocket.
-- @param msg The message to send. This may be either a JSON-serializable table
-- or a string.
-- @param binary (Boolean) Treat the message as binary data (use WebSocket binary
-- opcode).
-- If the connection has been closed a error is raised.
function websocket.WebSocketStream:write_message(msg, binary)
    if self._closed == true then
        error("WebSocket connection has been closed. Can not write message.")
    end
    if type(msg) == "table" then
        msg = escape.json_encode(msg)
    end
    self:_send_frame(true,
                     binary and
                        websocket.opcode.BINARY or websocket.opcode.TEXT,
                     msg)
end

--- Send a pong reply to the server.
function websocket.WebSocketStream:pong(data)
    self:_send_frame(true, websocket.opcode.PONG, data)
end

--- Send a ping to the connected client.
function websocket.WebSocketStream:ping(data, callback, callback_arg)
    self._ping_callback = callback
    self._ping_callback_arg = callback_arg
    self:_send_frame(true, websocket.opcode.PING, data)
end

--- Close the connection.
function websocket.WebSocketStream:close()
    self._closed = true
    local _self = self
    self:_send_frame(true, websocket.opcode.CLOSE, "", function()
        _self.stream:close()
    end)
end

--- Is the WebSocketStream closed?
-- @return true if closed, otherwise nil.
function websocket.WebSocketStream:closed()
    return self._closed
end

--- Accept a new WebSocket frame.
function websocket.WebSocketStream:_accept_frame(header)
    local ws_header = ffi.cast("struct ws_header *", header)
    self._final_bit = bit.band(ws_header.flags, 0x80) ~= 0
    self._rsv1_bit = bit.band(ws_header.flags, 0x40) ~= 0
    self._rsv2_bit = bit.band(ws_header.flags, 0x20) ~= 0
    self._rsv3_bit = bit.band(ws_header.flags, 0x10) ~= 0
    self._opcode = bit.band(ws_header.flags, 0xf)
    self._mask_bit = bit.band(ws_header.len, 0x80) ~= 0
    local payload_len = bit.band(ws_header.len, 0x7f)
    if self._opcode == websocket.opcode.CLOSE and payload_len >= 126 then
        self:_error(
            "WebSocket protocol error: \
            Received CLOSE opcode with greater than 126 payload.")
        return
    end
    if payload_len < 126 then
        self._payload_len = payload_len
        if self._mask_bit then
            self.stream:read_bytes(4, self._frame_mask_key, self)
        else
            self.stream:read_bytes(self._payload_len,
                                   self._frame_payload,
                                   self)
        end
    elseif payload_len == 126 then
        -- 16 bit length.
        self.stream:read_bytes(2, self._frame_len_16, self)
    elseif payload_len == 127 then
        -- 64 bit length.
        self.stream:read_bytes(8, self._frame_len_64, self)
    end
end

if le then
    local _tmp_convert_16 = ffi.new("uint16_t[1]")
    function websocket.WebSocketStream:_frame_len_16(data)
        -- Network byte order for multi-byte length values.
        -- What were they thinking!
        ffi.copy(_tmp_convert_16, data, 2)
        self._payload_len = tonumber(ffi.C.ntohs(_tmp_convert_16[0]))
        if self._mask_bit then
            self.stream:read_bytes(4, self._frame_mask_key, self)
        else
            self.stream:read_bytes(self._payload_len,
                                   self._frame_payload,
                                   self)
        end
    end

    local _tmp_convert_64 = ffi.new("uint64_t[1]")
    function websocket.WebSocketStream:_frame_len_64(data)
        ffi.copy(_tmp_convert_64, data, 8)
        self._payload_len = tonumber(
            ENDIAN_SWAP_U64(_tmp_convert_64[0]))
        if self._mask_bit then
            self.stream:read_bytes(4, self._frame_mask_key, self)
        else
            self.stream:read_bytes(self._payload_len,
                                   self._frame_payload,
                                   self)
        end
    end
elseif be then
    -- FIXME: Create funcs for BE.
end

function websocket.WebSocketStream:_frame_mask_key(data)
    self._frame_mask = data
    self.stream:read_bytes(self._payload_len, self._masked_frame_payload, self)
end

function websocket.WebSocketStream:_masked_frame_payload(data)
    local unmasked = _unmask_payload(self._frame_mask, data)
    self:_frame_payload(unmasked)
end

if le then
    -- Multi-byte lengths must be sent in network byte order, aka
    -- big-endian. Ugh...
    function websocket.WebSocketStream:_send_frame(finflag, opcode, data,
        callback, callback_arg)
        if self.stream:closed() then
            return
        end

        local data_sz = data:len()
        _ws_header.flags = bit.bor(finflag and 0x80 or 0x0, opcode)

        -- 7 bit.
        if data_sz < 0x7e then
            _ws_header.len = bit.bor(data_sz,
                                     self.mask_outgoing and 0x80 or 0x0)
            self.stream:write(ffi.string(_ws_header, 2))

        -- 16 bit
        elseif data_sz <= 0xffff then
            _ws_header.len = bit.bor(126, self.mask_outgoing and 0x80 or 0x0)
            _ws_header.ext_len.sh = data_sz
            _ws_header.ext_len.sh = ffi.C.htons(_ws_header.ext_len.sh)
            self.stream:write(ffi.string(_ws_header, 4))

        -- 64 bit
        else
            _ws_header.len = bit.bor(127, self.mask_outgoing and 0x80 or 0x0)
            _ws_header.ext_len.ll = data_sz
            _ws_header.ext_len.ll = ENDIAN_SWAP_U64(_ws_header.ext_len.ll)
            self.stream:write(ffi.string(_ws_header, 10))
        end

        if self.mask_outgoing == true then
            -- Create a random mask.
            local ws_mask = ffi.new("unsigned char[4]")
            ws_mask[0] = math.random(0x0, 0xff)
            ws_mask[1] = math.random(0x0, 0xff)
            ws_mask[2] = math.random(0x0, 0xff)
            ws_mask[3] = math.random(0x0, 0xff)
            self.stream:write(ffi.string(ws_mask, 4))
            self.stream:write(_unmask_payload(ws_mask, data), callback, callback_arg)
            return
        end

        -- Do not return until write is flushed to iostream :).
        self.stream:write(data, callback, callback_arg)
    end
elseif be then
    -- TODO: create websocket.WebSocketStream:_send_frame for BE.
end


--- WebSocket Server
-- Must be used in turbo.web.Application.
websocket.WebSocketHandler = class("WebSocketHandler", web.RequestHandler)
websocket.WebSocketHandler:include(websocket.WebSocketStream)

function websocket.WebSocketHandler:initialize(application,
                                               request,
                                               url_args,
                                               options)
    web.RequestHandler.initialize(self, application, request, url_args, options)
    self.stream = request.connection.stream
end

--- Called when a new websocket request is opened.
function websocket.WebSocketHandler:open() end

--- Called when a message is receive.
-- @param msg (String) The receive message.
function websocket.WebSocketHandler:on_message(msg) end

--- Called when the connection is closed.
function websocket.WebSocketHandler:on_close() end

--- Called when a error is raised.
function websocket.WebSocketHandler:on_error(msg) end

--- Called when the headers has been parsed and the server is about to initiate
-- the WebSocket specific handshake. Use this to e.g check if the headers
-- Origin field matches what you expect.
function websocket.WebSocketHandler:prepare() end

--- Called if the client have included a Sec-WebSocket-Protocol field
-- in header. This method will then receive a table of protocols that
-- the clients wants to use. If this field is not set, this method will
-- never be called. The return value of this method should be a string
-- which matches one of the suggested protcols in its parameter.
-- If all of the suggested protocols are unacceptable then dismissing of
-- the request is done by either raising error or returning nil.
function websocket.WebSocketHandler:subprotocol(protocols) end

--- Main entry point for the Application class.
function websocket.WebSocketHandler:_execute()
    if self.request.method ~= "GET" then
        error(web.HTTPError(
            405,
            "Method not allowed. Websocket supports GET only."))
    end
    local upgrade = self.request.headers:get("Upgrade")
    if not upgrade or upgrade:lower() ~= "websocket" then
        error(web.HTTPError(
            400,
            "Expected a valid \"Upgrade\" HTTP header."))
    end
    self.sec_websocket_key = self.request.headers:get("Sec-WebSocket-Key")
    if not self.sec_websocket_key then
        log.error("Client did not send a Sec-WebSocket-Key field. \
                   Probably not a Websocket requets, can not upgrade.")
        error(web.HTTPError(400, "Invalid protocol."))
    end
    self.sec_websocket_version =
        self.request.headers:get("Sec-WebSocket-Version")
    if not self.sec_websocket_version then
        log.error("Client did not send a Sec-WebSocket-Version field. \
                   Probably not a Websocket request, can not upgrade.")
        error(web.HTTPError(400,"Invalid protocol."))
    end
    if self.sec_websocket_version ~= "13" then
        log.error(strf(
            "Client wants to use not implemented Websocket Version %s.\
            Can not upgrade.", self.sec_websocket_version))
        -- Propose a specific version for the client...
        self:add_header("Sec-WebSocket-Version", "13")
        self:set_status_code(426)
        self:finish()
        return
    end
    local prot = self.request.headers:get("Sec-WebSocket-Protocol")
    if prot then
        prot = util.strsplit(prot, ",")
        for i=1, #prot do
            prot[i] = escape.trim(prot[i])
        end
        if #prot ~= 0 then
            local selected_protocol = self:subprotocol(prot)
            if not selected_protocol then
                log.warning(
                    "No acceptable subprotocols for WebSocket were found.")
                error(web.HTTPError(400, "Invalid subprotocol."))
            end
            self.subprotocol = selected_protocol
        end
    end
    -- Origin can be used by client applications to either accept or deny
    -- a request. This responsibility is left up to each developer to handle
    -- in e.g the prepare() method.
    self.origin = self.request.headers:get("Origin")
    self:prepare()
    local response_header = self:_create_response_header()
    self.stream:write(response_header.."\r\n")
    -- HTTP headers read, change to WebSocket protocol.
    -- Set max buffer size to 64MB as it is 16KB at this point...
    self.stream:set_max_buffer_size(1024*1024*64)
    log.success(string.format([[[websocket.lua] WebSocket opened %s (%s)]],
        self.request.headers:get_url(),
        self.request.remote_ip))
    self:_continue_ws()
end

function websocket.WebSocketHandler:_calculate_ws_accept()
    assert(escape.base64_decode(self.sec_websocket_key):len() == 16,
           "Sec-WebSocket-Key is of invalid size.")
    local hash = hash.SHA1(self.sec_websocket_key..websocket.MAGIC)
    return escape.base64_encode(hash:finalize(), 20)
end

function websocket.WebSocketHandler:_create_response_header()
    local header = httputil.HTTPHeaders()
    header:set_status_code(101)
    header:set_version("HTTP/1.1")
    header:add("Server", "Turbo v1.1")
    header:add("Upgrade", "websocket")
    header:add("Connection", "Upgrade")
    header:add("Sec-WebSocket-Accept", self:_calculate_ws_accept())
    if type(self.subprotocol) == "string"  then
        -- Set user selected subprotocol string.
        header:add("Sec-WebSocket-Protocol", self.subprotocol)
    end
    return header:stringify_as_response()
end

--- Error handler.
function websocket.WebSocketHandler:_error(msg)
    log.error("[websocket.lua] "..msg)
    if not self._closed == true and not self.stream:closed() then
        self:close()
    end
    self:on_error(msg)
end

function websocket.WebSocketHandler:_socket_closed()
    log.success(string.format([[[websocket.lua] WebSocket closed %s (%s) %dms]],
        self.request.headers:get_url(),
        self.request.remote_ip,
        self.request:request_time()))
    self:on_close()
end

--- Called after HTTP handshake has passed and connection has been upgraded
-- to WebSocket.
function websocket.WebSocketHandler:_continue_ws()
    self.stream:set_close_callback(self._socket_closed, self)
    self._fragmented_message_buffer = buffer(1024)
    self.stream:read_bytes(2, self._accept_frame, self)
    self:open()
end

function websocket.WebSocketHandler:_frame_payload(data)
    local opcode
    if self._opcode == websocket.opcode.CLOSE then
        if not self._final_bit then
            self:_error(
                "WebSocket protocol error: \
                CLOSE opcode was fragmented.")
            return
        end
        opcode = self._opcode
    elseif self._opcode == websocket.opcode.CONTINUE then
        if self._fragmented_message_buffer:len() == 0 then
            self:_error(
                "WebSocket protocol error: \
                CONTINUE opcode, but theres nothing to continue.")
            return
        end
        self._fragmented_message_buffer:append_luastr_right(data)
        if self._final_bit == true then
            opcode = self._fragmented_message_opcode
            data = self._fragmented_message_buffer:__tostring()
            self._fragmented_message_buffer:clear()
            self._fragmented_message_opcode = nil
        end
    else
        if self._fragmented_message_buffer:len() ~= 0 then
            self:_error(
                "WebSocket protocol error: \
                previous CONTINUE opcode not finished.")
            return
        end
        if self._final_bit == true then
            opcode = self._opcode
        else
            self._fragmented_message_opcode = self._opcode
            self._fragmented_message_buffer:append_luastr_right(data)
            if data:len() == 0 then
                log.debug("Zero length data on WebSocket.")
            end
        end
    end
    if self._final_bit == true then
        self:_handle_opcode(opcode, data)
    end
    if self._closed ~= true then
        self.stream:read_bytes(2, self._accept_frame, self)
    end
end

function websocket.WebSocketHandler:_handle_opcode(opcode, data)
    if self._closed == true then
        return
    end
    if opcode == websocket.opcode.TEXT or
            opcode == websocket.opcode.BINARY then
        self:on_message(data)
    elseif opcode == websocket.opcode.CLOSE then
        self:close()
    elseif opcode == websocket.opcode.PING then
        self:_send_frame(true, websocket.opcode.PONG, data)
    elseif opcode == websocket.opcode.PONG then
        if self._ping_callback then
            local callback = self._ping_callback
            local arg = self._ping_callback_arg
            self._ping_callback = nil
            self._ping_callback_arg = nil
            if arg then
                callback(arg, data)
            else
                callback(data)
            end
        end
    else
        self:_error(
            "WebSocket protocol error: \
            invalid opcode ".. tostring(opcode))
        return
    end
end


--- WebSocket Client.
-- Usage:
--  websocket.WebSocketClient("ws://websockethost.com/app", {
--      on_message =         function(self, msg) end,
--      on_error =           function(self, code, msg) end,
--      on_headers =         function(self, header) end,
--      on_connect =         function(self) end,
--      on_close =           function(self) end,
--      on_ping =            function(self, data) end,
--      modify_headers =     function(header) end,
--      request_timeout =    10,
--      connect_timeout =    10,
--      user_agent =         "Turbo WS Client v1.1",
--      cookie =             "Bla",
--      websocket_protocol = "meh"
--  })
websocket.WebSocketClient = class("WebSocketClient")
websocket.WebSocketClient:include(websocket.WebSocketStream)

function websocket.WebSocketClient:initialize(address, kwargs)
    self.mask_outgoing = true
    self.address = address
    self.kwargs = kwargs or {}
    self._connect_time = util.gettimemonotonic()
    self.http_cli = async.HTTPClient(self.kwargs.ssl_options,
                                     self.kwargs.ioloop,
                                     self.kwargs.max_buffer_size)
    local websocket_key = escape.base64_encode(util.rand_str(16))
    -- Reusing async.HTTPClient.
    local _modify_headers_success = true
    local res = coroutine.yield(self.http_cli:fetch(address, {
        keep_alive = true,
        allow_websocket_connect = true,
        request_timeout = self.kwargs.request_timeout,
        connect_timeout = self.kwargs.connect_timeout,
        cookie = self.kwargs.cookie,
        user_agent = self.kwargs.user_agent,
        allow_redirects = self.kwargs.allow_redirects,
        max_redirects = self.kwargs.max_redirects,
        on_headers = function(http_header)
            http_header:add("Upgrade", "Websocket")
            http_header:add("Connection", "Upgrade")
            http_header:add("Sec-WebSocket-Key", websocket_key)
            http_header:add("Sec-WebSocket-Version", "13")
            -- WebSocket Sub-Protocol handling...
            if type(self.kwargs.websocket_protocol) == "string" then
                http_header:add("Sec-WebSocket-Protocol",
                                self.kwargs.websocket_protocol)
            elseif self.kwargs.websocket_protocol then
                error("Invalid type of \"websocket_protocol\" value")
            end
            if type(self.kwargs.modify_headers) == "function" then
                -- User can modify header in callback.
                _modify_headers_success = self:_protected_call(
                    "modify_headers",
                    self.kwargs.modify_headers,
                    self,
                    http_header)
            end
        end
    }))
    if _modify_headers_success == false then
        -- Must do this outside callback to HTTPClient to get desired effect.
        -- In the event of error in "modify_headers" callback _error is already
        -- called.
        return
    end
    if res.error then
        -- HTTPClient error codes are compatible with WebSocket errors.
        -- Copy the error from HTTPClient and reuse for _error.
        self:_error(res.error.code, res.error.message)
        return
    end
    if res.code == 101 then
        -- Check accept key.
        local accept_key = res.headers:get("Sec-WebSocket-Accept")
        assert(accept_key,
               "Missing Sec-WebSocket-Accept header field.")
        local match = escape.base64_encode(
            hash.SHA1(websocket_key..websocket.MAGIC):finalize(), 20)
        assert(accept_key == match,
               "Sec-WebSocket-Accept does not match what was expected.")
        if type(self.kwargs.on_headers) == "function" then
            if not self:_protected_call("on_headers",
                                        self.kwargs.on_headers,
                                        self,
                                        res.headers) then
                return
            end
            if self:closed() then
                -- User closed the connection in on_headers callback. Just
                -- return as the connection is already closed off.
                return
            end
        end
    else
        -- Handle error.
        self:_error(websocket.errors.BAD_HTTP_STATUS,
                    strf("Excpected 101, was %d, can not upgrade.", res.code))
        return
    end
    -- Store ref. for IOStream in the HTTPClient.
    self.stream = self.http_cli.iostream
    assert(self.stream:closed() == false, "Connection were closed.")
    log.success(string.format(
        [[[websocket.lua] WebSocketClient connection open %s]],
        self.address))
    self:_continue_ws()
end

function websocket.WebSocketClient:_protected_call(name, func, arg, data)
    local status, err = pcall(func, arg, data)
    if status ~= true then
        local err_msg = strf(
            "WebSocketClient at %p unhandled error in callback \"%s\":\n",
            self,
            name)
        self:_error(websocket.errors.CALLBACK_ERROR,
                    err and err_msg .. err or err_msg)
        return false
    end
    return true
end

--- Called after HTTP handshake has passed and connection has been upgraded
-- to WebSocket.
function websocket.WebSocketClient:_continue_ws()
    self.stream:set_close_callback(self._socket_closed, self)
    self._fragmented_message_buffer = buffer(1024)
    self.stream:read_bytes(2, self._accept_frame, self)
    if type(self.kwargs.on_connect) == "function" then
        self:_protected_call("on_connect", self.kwargs.on_connect, self)
    end
end

function websocket.WebSocketClient:_error(code, msg)
    if self.stream then
        self.stream:close()
    end
    if type(msg) == "string" then
        log.error(msg)
    end
    if type(self.kwargs.on_error) == "function" then
        self.kwargs.on_error(self, code, msg)
    end
end

function websocket.WebSocketClient:_frame_payload(data)
    local opcode
    if self._opcode == websocket.opcode.CLOSE then
        if not self._final_bit then
            self:_error(websocket.errors.WEBSOCKET_PROTOCOL_ERROR,
                "WebSocket protocol error: \
                CLOSE opcode was fragmented.")
            return
        end
        opcode = self._opcode
    elseif self._opcode == websocket.opcode.CONTINUE then
        if self._fragmented_message_buffer:len() == 0 then
            self:_error(websocket.errors.WEBSOCKET_PROTOCOL_ERROR,
                "WebSocket protocol error: \
                CONTINUE opcode, but theres nothing to continue.")
            return
        end
        self._fragmented_message_buffer:append_luastr_right(data)
        if self._final_bit == true then
            opcode = self._fragmented_message_opcode
            data = self._fragmented_message_buffer:__tostring()
            self._fragmented_message_buffer:clear()
            self._fragmented_message_opcode = nil
        end
    else
        if self._fragmented_message_buffer:len() ~= 0 then
            self:_error(websocket.errors.WEBSOCKET_PROTOCOL_ERROR,
                "WebSocket protocol error: \
                previous CONTINUE opcode not finished.")
            return
        end
        if self._final_bit == true then
            opcode = self._opcode
        else
            self._fragmented_message_opcode = self._opcode
            self._fragmented_message_buffer:append_luastr_right(data)
            if data:len() == 0 then
                log.debug("Zero length data on WebSocket.")
            end
        end
    end
    if self._final_bit == true then
        self:_handle_opcode(opcode, data)
    end
    if self._closed ~= true then
        self.stream:read_bytes(2, self._accept_frame, self)
    end
end

function websocket.WebSocketClient:_handle_opcode(opcode, data)
    if self._closed == true then
        return
    end
    if opcode == websocket.opcode.TEXT or
            opcode == websocket.opcode.BINARY then
        if self.kwargs.on_message then
            self:_protected_call("on_message",
                                 self.kwargs.on_message,
                                 self,
                                 data)
        end
    elseif opcode == websocket.opcode.CLOSE then
        self:close()
    elseif opcode == websocket.opcode.PING then
        if self.kwargs.on_ping then
            self:_protected_call("on_ping",
                                 self.kwargs.on_ping,
                                 self,
                                 data)
        else
            self:pong(data)
        end
    elseif opcode == websocket.opcode.PONG then
        if self._ping_callback then
            local callback = self._ping_callback
            local arg = self._ping_callback_arg
            self._ping_callback = nil
            self._ping_callback_arg = nil
            if arg then
                callback(arg, data)
            else
                callback(data)
            end
        end
    else
        self:_error(websocket.errors.WEBSOCKET_PROTOCOL_ERROR,
            "WebSocket protocol error: \
            invalid opcode ".. tostring(opcode))
        return
    end
end

function websocket.WebSocketClient:_socket_closed()
    log.success(string.format(
        [[[websocket.lua] WebSocketClient closed %s %dms]],
        self.address,
        util.gettimemonotonic() - self._connect_time))
    if type(self.kwargs.on_close) == "function" then
        self:_protected_call("on_close", self.kwargs.on_close, self)
    end
end

return websocket
