--
-- lua-Spore : <http://fperrad.github.com/lua-Spore/>
--

local error = error
local pairs = pairs
local tostring = tostring
local random = require 'math'.random
local time = require 'os'.time
local tconcat = require 'table'.concat
local tsort = require 'table'.sort
local digest = require 'crypto'.hmac.digest
local mime = require 'mime'
local url = require 'socket.url'
local escape = require 'Spore.Request'.escape
local request = require 'Spore.Protocols'.request


local _ENV = nil
local m = {}

--[[
        Homepage: http://oauth.net/

        RFC 5849 : The OAuth 1.0 Protocol
--]]

function m.generate_timestamp ()
    return tostring(time())
end

function m.generate_nonce ()
    return digest('sha1', tostring(random()) .. 'random' .. tostring(time()), 'keyyyy')
end

function m:call (req)
    local env = req.env
    local spore = env.spore
    local oparams

    local function base_string ()
        local query_keys, query_vals = {}, {}
        local query_string = env.QUERY_STRING
        if query_string then
            for k, v in query_string:gmatch '([^=]+)=([^&]*)&?' do
                query_keys[#query_keys+1] = k
                query_vals[k] = v
            end
        end
        local payload = spore.payload
        if payload then
            local ct = req.headers['content-type']
            if not ct or ct == 'application/x-www-form-urlencoded' then
                for k, v in payload:gmatch '([^=&]+)=?([^&]*)&?' do
                    query_keys[#query_keys+1] = k
                    query_vals[k] = v:gsub('+', '%%20')
                end
            end
        end

        local scheme = spore.url_scheme
        local port = env.SERVER_PORT
        if port == '80' and scheme == 'http' then
            port = nil
        end
        if port == '443' and scheme == 'https' then
            port = nil
        end
        local base_url = url.build {
            scheme  = scheme,
            host    = env.SERVER_NAME,
            port    = port,
            path    = env.PATH_INFO,
            -- no query
        }
        for k, v in pairs(oparams) do
            query_keys[#query_keys+1] = k
            query_vals[k] = v
        end
        tsort(query_keys)
        local params = {}
        for i = 1, #query_keys do
            local k = query_keys[i]
            local v = query_vals[k]
            params[#params+1] = k .. '=' .. v
        end
        local normalized = tconcat(params, '&')

        return req.method:upper() .. '&' .. escape(base_url) .. '&' .. escape(normalized)
    end  -- base_string

    if spore.authentication
    and self.oauth_consumer_key and self.oauth_consumer_secret then
        oparams = {
            oauth_signature_method  = self.oauth_signature_method or 'HMAC-SHA1',
            oauth_consumer_key      = self.oauth_consumer_key,
            oauth_token             = self.oauth_token,
            oauth_verifier          = self.oauth_verifier,
        }
        if not oparams.oauth_token then
            oparams.oauth_callback  = self.oauth_callback or 'oob'      -- out-of-band
        end
        for k, v in pairs(oparams) do
            oparams[k] = escape(v)
        end

        req:finalize()

        local signature_key = escape(self.oauth_consumer_secret) .. '&' .. escape(self.oauth_token_secret or '')
        local oauth_signature
        if self.oauth_signature_method == 'PLAINTEXT' then
            oauth_signature = escape(signature_key)
        else
            oparams.oauth_timestamp = m.generate_timestamp()
            oparams.oauth_nonce = m.generate_nonce()
            local oauth_signature_base_string = base_string()
            if oparams.oauth_signature_method == 'HMAC-SHA1' then
                local hmac_binary = digest('sha1', oauth_signature_base_string, signature_key, true)
                local hmac_b64 = mime.b64(hmac_binary)
                oauth_signature = escape(hmac_b64)
            else
                error(oparams.oauth_signature_method .. " is not supported")
            end
            spore.oauth_signature_base_string = oauth_signature_base_string
        end

        local auth = 'OAuth'
        if self.realm then
            auth = auth .. ' realm="' .. tostring(self.realm) .. '",'
        end
        auth = auth ..  ' oauth_consumer_key="' .. oparams.oauth_consumer_key .. '"'
                    .. ', oauth_signature_method="' .. oparams.oauth_signature_method .. '"'
                    .. ', oauth_signature="' .. oauth_signature ..'"'
        if oparams.oauth_signature_method ~= 'PLAINTEXT' then
            auth = auth .. ', oauth_timestamp="' .. oparams.oauth_timestamp .. '"'
                        .. ', oauth_nonce="' .. oparams.oauth_nonce .. '"'
        end
        if not oparams.oauth_token then      -- 1) request token
            auth = auth .. ', oauth_callback="' .. oparams.oauth_callback .. '"'
        else
            if oparams.oauth_verifier then   -- 2) access token
                auth = auth .. ', oauth_token="' .. oparams.oauth_token .. '"'
                            .. ', oauth_verifier="' .. oparams.oauth_verifier .. '"'
            else                            -- 3) client requests
                auth = auth .. ', oauth_token="' .. oparams.oauth_token .. '"'
            end
        end
        req.headers['authorization'] = auth

        return request(req)
    end
end

return m
--
-- Copyright (c) 2010-2015 Francois Perrad
--
-- This library is licensed under the terms of the MIT/X11 license,
-- like Lua itself.
--
