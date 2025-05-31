--
-- lua-Spore : <http://fperrad.github.com/lua-Spore/>
--

local url = require 'socket.url'
local Protocols = require 'Spore.Protocols'


local _ENV = nil
local m = {}

m.max_redirect = 5

function m:call (req)
    local nredirect = 0

    return  function (res)
                while nredirect < m.max_redirect do
                    local location = res.headers and res.headers['location']
                    local status = res.status
                    if location and (status == 301 or status == 302
                                  or status == 303 or status == 307) then
                        if req.headers['host'] then
                            local uri = url.parse(location)
                            req.headers['host'] = uri.host
                            local proxy = url.parse(req.url)
                            uri.host = proxy.host
                            uri.port = proxy.port
                            req.url = url.build(uri)
                            req.env.spore.url_scheme = uri.scheme
                        else
                            req.url = url.absolute(req.url, location)
                            req.env.spore.url_scheme = url.parse(location).scheme
                        end
                        req.headers['cookie'] = nil
                        res = Protocols.request(req)
                        nredirect = nredirect + 1
                    else
                        break
                    end
                end
                return res
            end
end

return m
--
-- Copyright (c) 2010-2015 Francois Perrad
--
-- This library is licensed under the terms of the MIT/X11 license,
-- like Lua itself.
--
