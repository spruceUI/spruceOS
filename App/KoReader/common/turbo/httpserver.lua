--- Turbo.lua HTTP Server module
-- A non-blocking HTTPS Server based on the TCPServer class.
-- Supports HTTP/1.0 and HTTP/1.1.
-- Includes SSL support.
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

local tcpserver =   require "turbo.tcpserver"
local httputil =    require "turbo.httputil"
local ioloop =      require "turbo.ioloop"
local iostream =    require "turbo.iostream"
local util =        require "turbo.util"
local log =         require "turbo.log"
require('turbo.3rdparty.middleclass')

local httpserver = {} -- httpserver namespace

-- HTTPServer based on TCPServer, IOStream and IOLoop classes.
-- This class is used by the Application class to serve its RequestHandlers.
-- The server itself is only responsible for handling incoming requests, no
-- response to the request is produced, that is the purpose of the request
-- callback given as argument on initialization. The callback receives the
-- HTTPRequest class instance produced for the incoming request and can
-- by data provided in that instance decide on how it want to respond to
-- the client. The callback must produce a valid HTTP response header and
-- optionally a response body and use the HTTPRequest:write method.

-- The server supports SSL, HTTP/1.1 Keep-Alive and optionally HTTP/1.0
-- Keep-Alive if the header field is specified.

-- Example usage of HTTPServer:

-- local httpserver = require('turbo.httpserver')
-- local ioloop = require('turbo.ioloop')
-- local ioloop_instance = ioloop.instance()

-- function handle_request(request)
--     local message = "You requested: " .. request.path
--     request:write("HTTP/1.1 200 OK\r\nContent-Length:" .. message:len() ..
--          "\r\n\r\n")
--     request:write(message)
--     request:finish()
-- end

-- http_server = httpserver.HTTPServer:new(handle_request)
-- http_server:listen(8888)
-- ioloop_instance:start()
httpserver.HTTPServer = class('HTTPServer', tcpserver.TCPServer)

--- Create a new HTTPServer class instance.
-- @param request_callback (Function) Callback when requests are receive by
-- the server.
-- @param no_keep_alive (Boolean) If clients request use Keep-Alive it is to be
-- ignored.
-- @param io_loop (IOLoop instance) The IOLoop instance you want to use.
-- @param xheaders (Boolean) Care about X-* header fields or not.
-- @param kwargs (Table) Key word arguments.
-- Key word arguments supported:
-- "read_body" = Automatically read, and parse any request body. Default is
--      true. If set to false, the user must read the body from the connection
--      himself. Not reading a body in the case of a keep-alive request may
--      lead to undefined behaviour. The body should be read or connection
--      closed.
-- "max_header_size" = The maximum amount of bytes a header can be.
--      If exceeded, request is dropped.
-- "max_body_size" = The maxium amount of bytes a request body can be.
--      If exceeded, request is dropped. HAS NO EFFECT IF read_body IS FALSE.
-- "ssl_options" =
--      "key_file" = SSL key file if a SSL enabled server is wanted.
--      "cert_file" = Certificate file. key_file must also be set.
function httpserver.HTTPServer:initialize(request_callback,
                                          no_keep_alive,
                                          io_loop,
                                          xheaders,
                                          kwargs)
    self.request_callback = request_callback
    self.no_keep_alive = no_keep_alive
    self.xheaders = xheaders
    self.kwargs = kwargs
    tcpserver.TCPServer.initialize(self,
                                   io_loop,
                                   kwargs and kwargs.ssl_options)
end

--- Internal handle_stream method to be called by super class TCPServer on new
-- connection.
-- @param stream (IOStream instance) Stream for the newly connected client.
-- @param address (String) IP address of newly connected client.
function httpserver.HTTPServer:handle_stream(stream, address)
    local http_conn = httpserver.HTTPConnection(
        stream,
        address,
        self.request_callback,
        self.no_keep_alive,
        self.xheaders,
        self.kwargs)
end


--- HTTPConnection class.
-- Represents a live connection to the server. Basically a helper class to
-- HTTPServer. It uses the IOStream class's callbacks to handle the different
-- sections of a HTTP request.
httpserver.HTTPConnection = class('HTTPConnection')

function httpserver.HTTPConnection:initialize(stream, address,
    request_callback, no_keep_alive, xheaders, kwargs)
    self.stream = stream
    self.address = address
    self.request_callback = request_callback
    self.no_keep_alive = no_keep_alive or false
    self.xheaders = xheaders or false
    self._request_finished = false
    self._header_callback = self._on_headers
    self.kwargs = kwargs or {}
    self.stream:set_maxed_buffer_callback(self._on_max_buffer, self)
    -- 18K max header size by default.
    self.stream:set_max_buffer_size(self.kwargs.max_header_size or 1024*18)
    self.stream:read_until("\r\n\r\n", self._header_callback, self)
end

function httpserver.HTTPConnection:_set_write_callback(callback, arg)
    self._write_callback = callback
    self._write_callback_arg = arg
end

function httpserver.HTTPConnection:_clear_write_callback()
    self._write_callback = nil
    self._write_callback_arg = nil
end

--- Writes a chunk of output to the underlying stream.
-- @param chunk (String) Data chunk to write to underlying IOStream.
-- @param callback (Function) Optional function called when buffer is fully
-- flushed.
-- @param arg Optional first argument for callback.
function httpserver.HTTPConnection:write(chunk, callback, arg)
    if not self._request then
        error("Request closed.")
    end
    if not self.stream:closed() then
        self:_set_write_callback(callback, arg)
        self.stream:write(chunk, self._on_write_complete, self)
    end
end

--- Write the given ``turbo.structs.buffer`` to the underlying stream.
-- @param buf (Buffer class instance)
-- @param callback (Function) Optional function called when buffer is fully
-- flushed.
-- @param arg Optional first argument for callback.
function httpserver.HTTPConnection:write_buffer(buf, callback, arg)
    if not self._request then
        error("Request closed.")
    end
    if not self.stream:closed() then
        self:_set_write_callback(callback, arg)
        self.stream:write_buffer(buf, self._on_write_complete, self)
    end
end

--- Write a Buffer class instance without copying it into the IOStream internal
-- buffer. Some considerations has to be done when using this. Any prior calls
-- to HTTPConnection:write or HTTPConnection:write_buffer must have completed
-- before this method can be used. The zero copy write must complete before any
-- other writes may be done. Also the buffer class should not be modified
-- while the write is being completed. Failure to follow these advice will lead
-- to undefined behaviour.
-- @param buf (Buffer class instance)
-- @param callback (Function) Optional function called when buffer is fully
-- flushed.
-- @param arg Optional first argument for callback.
function httpserver.HTTPConnection:write_zero_copy(buf, callback, arg)
    if not self._request then
        error("Request closed.")
    end
    if not self.stream:closed() then
        self:_set_write_callback(callback, arg)
        self.stream:write_zero_copy(buf, self._on_write_complete, self)
    else
        log.devel("[httpserver.lua] Trying to do zero copy operation on closed stream.")
    end
end

--- Finishes the request.
function httpserver.HTTPConnection:finish()
    assert(self._request, "Request closed")
    self._request_finished = true
    if not self.stream:writing() then
        self:_clear_write_callback()
        self:_finish_request()
    end
end

local function _on_headers_error_handler(err)
    log.error(string.format("[httpserver.lua] Invalid request. %s", err))
end

--- Handles incoming headers. The HTTPHeaders class is used to parse
-- request headers.
function httpserver.HTTPConnection:_on_headers(data)
    local headers
    local status, headers = xpcall(httputil.HTTPParser,
        _on_headers_error_handler, data, httputil.hdr_t["HTTP_REQUEST"])

    if status == false then
        -- Invalid headers. Close stream.
        -- Log line is printed by error handler describing the reason.
        self.stream:close()
        return
    end
    self._headers_read = true
    self._request = httpserver.HTTPRequest:new(headers:get_method(),
        headers:get_url(), {
            version = headers:get_version(),
            connection = self,
            headers = headers,
            remote_ip = self.address
        })
    if self.kwargs.read_body ~= false then
        local content_length = headers:get("Content-Length")
        if content_length then
            content_length = tonumber(content_length)
            -- Set max buffer size to 128MB.
            self.stream:set_max_buffer_size(
                self.kwargs.max_body_size or math.max(content_length, 1024*18))
            if content_length > self.stream.max_buffer_size then
                log.error(
                    "[httpserver.lua] Content-Length too long \
                    compared to current max body size.")
                self.stream:close()
            end
            if headers:get("Expect") == "100-continue" then
                self.stream:write("HTTP/1.1 100 (Continue)\r\n\r\n")
            end
            self.stream:read_bytes(content_length, self._on_request_body, self)
            return
        end
    end
    self.request_callback(self._request)
end

--- Handles incoming request body.
function httpserver.HTTPConnection:_on_request_body(data)
    self._request.body = data
    local content_type = self._request.headers:get("Content-Type")
    if content_type then
        if content_type:find("x-www-form-urlencoded", 1, true) then
            self.arguments =
                httputil.parse_post_arguments(self._request.body) or {}
        elseif content_type:find("multipart/form-data", 1, true) then
            -- Valid boundary must only be max 70 characters not
            -- ending in space.
            -- Valid characters from RFC2046 are:
            -- bchar := DIGIT / ALPHA / "'" / "(" / ")" /
            --          "+" / "_" / "," / "-" / "." /
            --          "/" / ":" / "=" / "?" / " "
            -- Boundary string is permitted to be quoted.
            local boundary =
                content_type:match(
                    "boundary=[\"]?([0-9a-zA-Z'()+_,-./:=? ]*[0-9a-zA-Z'()+_,-./:=?])")
            self.arguments =
                httputil.parse_multipart_data(self._request.body, boundary)
                    or {}
        end
    end
    self.request_callback(self._request)
end

--- Finish request.
function httpserver.HTTPConnection:_finish_request()
    local disconnect = false

    if self.no_keep_alive then
        disconnect = true
    else
        local connection_header = self._request.headers:get("Connection")
        if connection_header then
            connection_header = connection_header:lower()
        end
        if self._request:supports_http_1_1() then
            disconnect = connection_header == "close"
        elseif self._request.headers:get("Content-Length") or
            self._request.headers.method == "HEAD" or
                self._request.method == "GET" then
            disconnect = connection_header ~= "keep-alive"
        else
            disconnect = true
        end
    end
    self._max_buf = false
    self._request_finished = false
    if disconnect then
        self.stream:close()
        return
    end
    self.arguments = nil  -- Reset table in case of keep-alive.
    if not self.stream:closed() then
        self.stream:set_max_buffer_size(self.kwargs.max_header_size or 1024*18)
        self.stream:read_until("\r\n\r\n", self._header_callback, self)
    else
        log.debug("[httpserver.lua] Client hang up. End Keep-Alive session.")
        self = nil
        return
    end
end

--- Callback for on complete event.
function httpserver.HTTPConnection:_on_write_complete()
    if self._write_callback then
        local callback = self._write_callback
        local argument = self._write_callback_arg
        self:_clear_write_callback()
        callback(argument)
    end
    if self._request_finished and not self.stream:writing() then
        self:_finish_request()
    end
end

--- Callback for maxed out buffer.
function httpserver.HTTPConnection:_on_max_buffer()
    if self._max_buf then
        -- Allow one iteration of buffer at max. In case headers
        -- and body arrive in one chunk.
        if not self._headers_read then
            log.error(
                string.format("[httpserver.lua] Headers too large for limit %dB.",
                              self.kwargs.max_header_size or 1024*18))
        else
            log.error(
                string.format("[httpserver.lua] Request body too large for limit %dB.",
                              self.kwargs.max_header_size or 1024*18))
        end
        self.stream:close()
        return
    end
    self._max_buf = true
end

--- HTTPRequest class.
-- Represents a HTTP request to the server.
-- HTTP headers are parsed magically if headers are supplied with kwargs table.
httpserver.HTTPRequest = class('HTTPRequest')

--- Create a new HTTPRequest class instance.
-- @param method (String) HTTP request method, e.g "POST".
-- @param uri (String) The URI requested.
-- @param args (Table) Table or optional arguments:
-- Arguments available:
--         headers,
--         body,
--         remote_ip,
--         protocol,
--         host,
--         files,
--         connection
function httpserver.HTTPRequest:initialize(method, uri, args)
    local headers, body, remote_ip, protocol, host, files, version, connection
        = nil, nil, nil, nil, nil, nil, "HTTP/1.0", nil

    -- Find arguments sent.
    if type(args) == "table" then
        version = args.version or version
        headers = args.headers
        body = args.body
        remote_ip = args.remote_ip
        protocol = args.protocol
        host = args.host
        files = args.files
        connection = args.connection
    end
    self.method = method
    self.uri = uri
    self.version = args.version or version
    self.headers = headers or httputil.HTTPHeaders:new()
    self.body = body or ""
    if connection and connection.xheaders then
        self.remote_ip = self.headers:get("X-Real-Ip") or
            self.headers:get("X-Forwarded-For")
        if not self:_valid_ip(self.remote_ip) then
            self.remote_ip = remote_ip
        end
        self.protocol = self.headers:get("X-Scheme") or
            self.headers:get("X-Forwarded-Proto")
        if self.protocol ~= "http" or self.protocol ~= "https" then
            self.protocol = "http"
        end
    else
        self.remote_ip = remote_ip
        if protocol then
            self.protocol = protocol
        elseif connection and
            instanceOf(iostream.SSLIOStream, connection.stream) then
            self.protocol = "https"
        else
            self.protocol = "http"
        end
    end
    self.host = host or self.headers:get("Host") or "127.0.0.1"
    self.files = files or {}
    self.connection = connection
    self._start_time = util.gettimemonotonic()
    self._finish_time = nil
    self.path = self.headers:get_url_field(httputil.UF.PATH)
    self.arguments = self.headers:get_arguments()
end


---  Returns true if requester supports HTTP 1.1.
-- @return (Boolean)
function httpserver.HTTPRequest:supports_http_1_1()
    return self.version == "HTTP/1.1"
end

--- Writes a chunk of output to the stream.
-- @param chunk (String) Data chunk to write to underlying IOStream.
-- @param callback (Function) Optional callback called when socket is flushed.
function httpserver.HTTPRequest:write(chunk, callback, arg)
    self.connection:write(chunk, callback, arg)
end


--- Write a Buffer class instance to the stream.
-- @param buf (Buffer class instance)
-- @param callback Optional callback when socket is flushed.
-- @param arg Optional first argument for callback.
function httpserver.HTTPRequest:write_buffer(buf, callback, arg)
    self.connection:write_buffer(buf, callback, arg)
end

--- Write a Buffer class instance without copying it into the IOStream internal
-- buffer. Some considerations has to be done when using this. Any prior calls
-- to HTTPConnection:write or HTTPConnection:write_buffer must have completed
-- before this method can be used. The zero copy write must complete before any
-- other writes may be done. Also the buffer class should not be modified
-- while the write is being completed. Failure to follow these advice will lead
-- to undefined behaviour.
-- @param buf (Buffer class instance)
-- @param callback Optional callback when socket is flushed.
-- @param arg Optional first argument for callback.
function httpserver.HTTPRequest:write_zero_copy(buf, callback, arg)
    self.connection:write_zero_copy(buf, callback, arg)
end

--- Finish the request. Close connection.
function httpserver.HTTPRequest:finish()
    self.connection:finish()
    self._finish_time = util.gettimemonotonic()
end

--- Return the full URL that the user requested.
function httpserver.HTTPRequest:full_url()
    return self.protocol .. "://" .. self.host .. self.uri
end

--- Return the time used to handle the request or the
-- time up to now if request not finished.
-- @return (Number) Ms the request took to finish, or up until now if not yet
-- completed.
function httpserver.HTTPRequest:request_time()
    if not self._finish_time then
        return util.gettimemonotonic() - self._start_time
    else
        return self._finish_time - self._start_time
    end
end

function httpserver.HTTPRequest:_valid_ip(ip)
    --FIXME: This IP validation is broken!
    local ip = ip or ''
    return ip:find("[%d+%.]+") or nil
end

return httpserver
