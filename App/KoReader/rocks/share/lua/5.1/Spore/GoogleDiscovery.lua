
--
-- lua-Spore : <http://fperrad.github.com/lua-Spore>
--

local error = error
local pairs = pairs
local type = type
local checktype = require 'Spore'.checktype
local new_from_lua = require 'Spore'.new_from_lua
local slurp = require 'Spore.Protocols'.slurp
local decode = require 'json'.decode


local _ENV = nil
local m = {}

local expected_status = {
    GET     = { 200, 404 },
    DELETE  = { 204 },
}

local function convert (gdoc)
    local meta
    local documentation = gdoc.documentationLink
    if documentation then
        meta = {
            documentation = documentation,
        }
    end
    local spore = {
        name = gdoc.title,
        version = gdoc.version,
        description = gdoc.description,
        base_url = 'https://www.googleapis.com' .. gdoc.basePath,
        methods = {},
        meta = meta,
    }

    local function populate (resources)
        for _, resource in pairs(resources) do
            if not resource.methods then
                populate(resource)
            else
                for _, meth in pairs(resource.methods) do
                    local methname = meth.id:gsub('%w+%.', '', 1):gsub('%.', '_')
                    local required_params
                    local optional_params = { 'alt', 'fields', 'key', 'prettyPrint', 'userIp' }
                    for pname, param in pairs(meth.parameters or {}) do
                        if param.required then
                            if not required_params then
                                required_params = {}
                            end
                            required_params[#required_params+1] = pname
                        else
                            optional_params[#optional_params+1] = pname
                        end
                    end
                    spore.methods[methname] = {
                        path = meth.path:gsub('{([%w_]+)}', ':%1'),
                        method = meth.httpMethod,
                        required_params = required_params,
                        optional_params = optional_params,
                        required_payload = (meth.httpMethod == 'POST')
                                        or (meth.httpMethod == 'PUT')
                                        or nil,
                        expected_status = expected_status[meth.httpMethod],
                    }
                end
            end
        end
    end  -- populate

    populate(gdoc.resources)
    return spore
end
m.convert = convert

function m.new_from_discovery (api, opts)
    opts = opts or {}
    checktype('new_from_discovery', 2, opts, 'table')
    if type(api) == 'string' then
        local content = slurp(api)
        return new_from_lua(convert(decode(content)), opts)
    end
    if type(api) == 'table' then
        local discovery = new_from_lua {
            base_url = 'https://www.googleapis.com/discovery/v1/',
            methods = {
                get = {
                    path = 'apis/:api/:version/rest',
                    method = 'GET',
                    required_params = { 'api', 'version' },
                    expected_status = { 200 },
                },
            },
        }
        discovery:enable 'Format.JSON'
        local r = discovery:get(api)
        return new_from_lua(convert(r.body), opts)
    end
    error("bad argument #1 to new_from_discovery (string or table expected, got "
          .. type(api) .. ")")
end

return m
--
-- Copyright (c) 2011-2018 Francois Perrad
--
-- This library is licensed under the terms of the MIT/X11 license,
-- like Lua itself.
--
