--- Turbo Web Cryto module
-- C defs for LuaJIT FFI and wrappers.
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

local ffi = require "ffi"
local log = require "turbo.log"
local platform = require "turbo.platform"
require "turbo.cdef"

local crypto = {} -- crypto namespace

local ok, ssl = pcall(require, "ssl")
if not ok then
    log.error(
        "Could not load \"ssl\" module (LuaSec). Exiting. "..
        "Please install module to enable SSL in Turbo.")
    os.exit(1)
end

local default_ca_path = "/etc/ssl/certs/ca-certificates.crt"
local env_ca_path = os.getenv("TURBO_CAPATH")
if env_ca_path then
    default_ca_path = env_ca_path
end

--- Create a client type SSL context.
-- @param cert_file (optional) Certificate file
-- @param prv_file (optional) Key file
-- @param ca_cert_path (optional) Path to CA certificates, or the system
-- wide in /etc/ssl/certs/ca-certificates.crt will be used.
-- @param verify (optional) Verify the hosts certificate with CA.
-- @param sslv (optional) SSL version to use.
-- @return Return code. 0 if successfull, else a error code and a
-- SSL error string, or -1 and a error string.
-- @return Allocated SSL_CTX *. Must not be freed. It is garbage collected.
function crypto.ssl_create_client_context(
        cert_file,
        prv_file,
        ca_cert_path,
        verify, sslv)
    local params = {
        mode = "client",
        protocol = "sslv23",
        key = prv_file,
        certificate = cert_file,
        cafile = ca_cert_path or default_ca_path,
        verify = verify and {"peer", "fail_if_no_peer_cert"} or nil,
        options = {"all"},
    }

    local ctx, err = ssl.newcontext(params)
    if not ctx then
        return -1, err
    else
        return 0, ctx
    end
end

--- Create a server type SSL context.
-- @param cert_file Certificate file (public key)
-- @param prv_file Key file (private key)
-- @param ca_cert_path (optional) Path to CA certificates, or the system
-- wide in /etc/ssl/certs/ca-certificates.crt will be used.
-- @param sslv (optional) SSL version to use.
-- @return Return code. 0 if successfull, else a OpenSSL error
-- code and a SSL
-- error string, or -1 and a error string.
-- @return Allocated SSL_CTX *. Must not be freed. It is garbage collected.
function crypto.ssl_create_server_context(cert_file, prv_file, ca_cert_path, sslv)
    local params = {
        mode = "server",
        protocol = "sslv23",
        key = prv_file,
        certificate = cert_file,
        cafile = ca_cert_path or default_ca_path,
        options = {"all"},
    }

    local ctx, err = ssl.newcontext(params)
    if not ctx then
        return -1, err
    else
        return 0, ctx
    end
end

function crypto.ssl_new(ctx, fd_sock, client)
    local peer = ssl.wrap(fd_sock, ctx)
    peer:settimeout(0)
    return peer
end

function crypto.ssl_do_handshake(SSLIOStream)
    local sock = SSLIOStream._ssl
    local res, err = sock:dohandshake()
    return res, err
end

return crypto
