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
local platform = require "turbo.platform"
local socket = require "turbo.socket_ffi"
local util = require "turbo.util"
require "turbo.cdef"

local crypto = {} -- crypto namespace

local lssl = ffi.load(os.getenv("TURBO_LIBSSL") or "ssl")
local libtffi = util.load_libtffi()

local EWOULDBLOCK, EINPROGRESS, ECONNRESET =
   socket.EWOULDBLOCK, socket.EINPROGRESS, socket.ECONNRESET

crypto.X509_FILETYPE_PEM =          1
crypto.X509_FILETYPE_ASN1 =         2
crypto.X509_FILETYPE_DEFAULT =      3
crypto.SSL_FILETYPE_ASN1 =          crypto.X509_FILETYPE_ASN1
crypto.SSL_FILETYPE_PEM =           crypto.X509_FILETYPE_PEM
crypto.SSL_ERROR_NONE =             0
crypto.SSL_ERROR_SSL =              1
crypto.SSL_ERROR_WANT_READ =        2
crypto.SSL_ERROR_WANT_WRITE =       3
crypto.SSL_ERROR_WANT_X509_LOOKUP = 4
crypto.SSL_ERROR_SYSCALL =          5
crypto.SSL_ERROR_ZERO_RETURN =      6
crypto.SSL_ERROR_WANT_CONNECT =     7
crypto.SSL_ERROR_WANT_ACCEPT =      8
-- use either SSL_VERIFY_NONE or SSL_VERIFY_PEER, the last 2 options
-- are 'ored' with SSL_VERIFY_PEER if they are desired
crypto.SSL_VERIFY_NONE =        0x00
crypto.SSL_VERIFY_PEER =        0x01
crypto.SSL_VERIFY_FAIL_IF_NO_PEER_CERT = 0x02
crypto.SSL_VERIFY_CLIENT_ONCE =     0x04
crypto.validate =
{
    ["MatchFound"] = 0,
    ["MatchNotFound"] = 1,
    ["NoSANPresent"] = 2,
    ["MalformedCertificate"] = 3,
    ["Error"] = 4
}

crypto.ERR_get_error = lssl.ERR_get_error
crypto.SSL_get_error = lssl.SSL_get_error
crypto.lib = lssl

--- Convert OpenSSL unsigned long error to string.
-- @param rc unsigned long error from OpenSSL library.
-- @returns Lua string.
function crypto.ERR_error_string(rc)
    local buf = ffi.new("char[256]")
    lssl.ERR_error_string_n(rc, buf, ffi.sizeof(buf))
    return ffi.string(buf)
end

--- Initialize the SSL library.
-- Can be called multiple times without causing any pain. If the library is
-- already loaded it will pass.
function crypto.ssl_init()
    if not _G._TURBO_SSL_INITED then
       _TURBO_SSL_INITED = true
        lssl.SSL_load_error_strings()
        lssl.SSL_library_init()
        lssl.OPENSSL_add_all_algorithms_noconf()
    end
end
if _G.TURBO_SSL then
    crypto.ssl_init()
end

--- Create a client type SSL context.
-- @param cert_file (optional) Certificate file
-- @param prv_file (optional) Key file
-- @param ca_cert_path (optional) Path to CA certificates, or the system
-- wide in /etc/ssl/certs/ca-certificates.crt will be used.
-- @param verify (optional) Verify the hosts certificate with CA.
-- @param sslv (optional) SSL version to use.
-- @return Return code. 0 if successfull, else a OpenSSL error code and a
-- SSL error string, or -1 and a error string.
-- @return Allocated SSL_CTX *. Must not be freed. It is garbage collected.
function crypto.ssl_create_client_context(
        cert_file,
        prv_file,
        ca_cert_path,
        verify, sslv)
    local meth
    local ctx
    local err = 0
    -- Use standardish path to ca-certificates if not specified by user.
    -- May not be present on all Unix systems.
    ca_cert_path = ca_cert_path or "/etc/ssl/certs/ca-certificates.crt"
    meth = sslv or lssl.SSLv23_client_method()
    if meth == nil then
        err = lssl.ERR_peek_error()
        lssl.ERR_clear_error()
        return err, crypto.ERR_error_string(err)
    end
    ctx = lssl.SSL_CTX_new(meth)
    if ctx == nil then
        err = lssl.ERR_peek_error()
        lssl.ERR_clear_error()
        return err, crypto.ERR_error_string(err)
    else
        ffi.gc(ctx, lssl.SSL_CTX_free)
    end
    -- If client certificates are set, load them and verify.
    if type(cert_file) == "string" and type(prv_file) == "string" then
        if lssl.SSL_CTX_use_certificate_file(ctx, cert_file,
            crypto.SSL_FILETYPE_PEM) <= 0 then
            err = lssl.ERR_peek_error()
            lssl.ERR_clear_error()
            return err, crypto.ERR_error_string(err)
        end
        if lssl.SSL_CTX_use_PrivateKey_file(ctx, prv_file,
            crypto.SSL_FILETYPE_PEM) <= 0 then
            err = lssl.ERR_peek_error()
            lssl.ERR_clear_error()
            return err, crypto.ERR_error_string(err)
        end
        -- Check if pub and priv key matches each other.
        if lssl.SSL_CTX_check_private_key(ctx) ~= 1 then
            return -1, "Private and public keys does not match"
        end
    end
    if verify == true then
        if lssl.SSL_CTX_load_verify_locations(ctx,
                ca_cert_path, nil) ~= 1 then
            err = lssl.ERR_peek_error()
            lssl.ERR_clear_error()
            return err, crypto.ERR_error_string(err)
        end
        lssl.SSL_CTX_set_verify(ctx, crypto.SSL_VERIFY_PEER, nil);
    end
    return err, ctx
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
    local meth
    local ctx
    local err = 0

    if not cert_file then
        return -1, "No cert file given in arguments";
    elseif not prv_file then
        return -1, "No priv file given in arguments";
    end
    meth = sslv or lssl.SSLv23_server_method()
    if meth == nil then
        err = lssl.ERR_peek_error()
        lssl.ERR_clear_error()
        return err, crypto.ERR_error_string(err)
    end
    ctx = lssl.SSL_CTX_new(meth)
    if ctx == nil then
        err = lssl.ERR_peek_error()
        lssl.ERR_clear_error()
        return err, crypto.ERR_error_string(err)
    else
        ffi.gc(ctx, lssl.SSL_CTX_free)
    end
    if lssl.SSL_CTX_use_certificate_file(ctx, cert_file,
        crypto.SSL_FILETYPE_PEM) <= 0 then
        err = lssl.ERR_peek_error()
        lssl.ERR_clear_error()
        return err, crypto.ERR_error_string(err)
    end
    if lssl.SSL_CTX_use_certificate_chain_file(ctx, cert_file) <= 0 then
        err = lssl.ERR_peek_error()
        lssl.ERR_clear_error()
        return err, crypto.ERR_error_string(err)
    end
    if lssl.SSL_CTX_use_PrivateKey_file(ctx, prv_file,
        crypto.SSL_FILETYPE_PEM) <= 0 then
        err = lssl.ERR_peek_error()
        lssl.ERR_clear_error()
        return err, crypto.ERR_error_string(err)
    end
    return err, ctx
end

function crypto.ssl_new(ctx, fd_sock, client)
    local ssl
    local err

    ssl = crypto.lib.SSL_new(ctx)
    if ssl == nil then
        err = crypto.lib.ERR_peek_error()
        crypto.lib.ERR_clear_error()
        error(string.format(
            "Could not do SSL handshake. Failed to create SSL*. %s",
            crypto.ERR_error_string(err)))
    end

    ffi.gc(ssl, crypto.lib.SSL_free)

    if crypto.lib.SSL_set_fd(ssl, fd_sock) <= 0 then
        err = crypto.lib.ERR_peek_error()
        crypto.lib.ERR_clear_error()
        error(string.format(
            "Could not do SSL handshake. \
                Failed to set socket fd to SSL*. %s",
            crypto.ERR_error_string(err)))
    end

    if client then
        crypto.lib.SSL_set_connect_state(ssl)
    else
        crypto.lib.SSL_set_accept_state(ssl)
    end
    return ssl
end

function crypto.ssl_do_handshake(SSLIOStream)
    local err = 0
    local errno
    local rc = 0
    local ssl = SSLIOStream._ssl
    local client = SSLIOStream._ssl_options._type == 1

    -- This method might be called multiple times if we recieved
    -- EINPROGRESS or equaivalent on prior calls. The OpenSSL
    -- documentation states that SSL_do_handshake should be called again
    -- when its needs are satisfied.
    rc = crypto.lib.SSL_do_handshake(ssl)
    if rc <= 0 then
        if client and SSLIOStream._ssl_verify then
            local verify_err = crypto.lib.SSL_get_verify_result(ssl)
            if verify_err ~= 0 then
                error(
                    string.format(
                        "SSL certificate chain validation failed: %s",
                        ffi.string(
                            crypto.lib.X509_verify_cert_error_string(
                                verify_err))))
            end
        end
        err = crypto.lib.SSL_get_error(ssl, rc)
        -- In case the socket is O_NONBLOCK break out when we get
        -- SSL_ERROR_WANT_* or equal syscall return code.
        if err == crypto.SSL_ERROR_WANT_READ or
            err == crypto.SSL_ERROR_WANT_READ then
            return false
        elseif err == crypto.SSL_ERROR_SYSCALL then
            -- Error on socket.
            errno = ffi.errno()
            if errno == EWOULDBLOCK or errno == EINPROGRESS then
                return false
            elseif errno == ECONNRESET then
                SSLIOStream:close()
                return false
            elseif errno ~= 0 then
                local fd = SSLIOStream.socket
                SSLIOStream:close()
                error(
                    string.format("Error when reading from fd %d. "..
                        "Errno: %d. %s",
                        fd,
                        errno,
                        socket.strerror(errno)))
            else
                -- Popular belief ties this branch to disconnects before
                -- handshake is completed.
                local fd = SSLIOStream.socket
                SSLIOStream:close()
                error(string.format(
                    "Could not do SSL handshake. "..
                        "Client connection closed.",
                    fd,
                    errno,
                    socket.strerror(errno)))
            end
        elseif err == crypto.SSL_ERROR_SSL then
            err = crypto.lib.ERR_peek_error()
            crypto.lib.ERR_clear_error()
            error(
                string.format("Could not do SSL handshake. SSL error. %s",
                crypto.ERR_error_string(err)))
        else
            error(string.format(
                "Could not do SSL handshake. SSL_do_hanshake returned %d",
                err))
        end
    else
        if client and SSLIOStream._ssl_verify then
            rc = libtffi.validate_hostname(SSLIOStream._ssl_hostname, ssl)
            if rc ~= crypto.validate.MatchFound then
                error("SSL certficate hostname validation failed, rc " ..
                tonumber(rc))
            end
        end
    end
    return true
end

--- Write data to a SSL connection.
-- @param ssl (SSL *) OpenSSL struct SSL ptr.
-- @param buf (const char *) Buffer to send.
-- @param sz (Number) Bytes to send from buffer.
function crypto.SSL_write(ssl, buf, sz)
    if ssl == nil or buf == nil then
        error("SSL_write passed null pointer.")
    end
    return lssl.SSL_write(ssl, buf, sz)
end

--- Read data from a SSL connection.
-- @param ssl (SSL *) OpenSSL struct SSL ptr.
-- @param buf (char *) Buffer to read to.
-- @param sz (Number) Bytes to maximum read into buffer.
    function crypto.SSL_read(ssl, buf, sz)
        if ssl == nil or buf == nil then
        error("SSL_read passed null pointer.")
    end
    return lssl.SSL_read(ssl, buf, sz)
end

return crypto
