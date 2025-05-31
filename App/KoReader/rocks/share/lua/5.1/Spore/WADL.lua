
--
-- lua-Spore : <http://fperrad.github.com/lua-Spore>
--
-- Web Application Description Language
-- see http://www.w3.org/Submission/wadl/

-- LIMITATION: cross-references are not supported

local assert = assert
local ipairs = ipairs
local tonumber = tonumber
local checktype = require 'Spore'.checktype
local new_from_lua = require 'Spore'.new_from_lua
local slurp = require 'Spore.Protocols'.slurp
local parse = require 'Spore.XML'.parse

local _ENV = nil
local m = {}

local function convert_uri_template (uri)
    -- see RFC 6570
    return uri:gsub('{([%w_]+)}', ':%1')
end

local function convert (doc)
    local wadl = assert(parse(doc))
    wadl = assert(wadl.application)
    local base_url
    local spore = {
        methods = {},
    }

    local function get_params (params, required_prm, optional_prm)
        local function clone (t)
            if t then
                local r = {}
                for i = 1, #t do
                    r[i] = t[i]
                end
                return r
            end
        end -- clone

        local required_params = clone(required_prm)
        local optional_params = clone(optional_prm)
        for _, param in ipairs(params or {}) do
            if param.style ~= 'header' then
                if param.required and (param.required == 'true'
                                    or param.required == '1') then
                    if not required_params then
                        required_params = {}
                    end
                    required_params[#required_params+1] = param.name
                else
                    if not optional_params then
                        optional_params = {}
                    end
                    optional_params[#optional_params+1] = param.name
                end
            end
        end
        return required_params, optional_params
    end -- get_params

    local function populate (methods, path, required_prm, optional_prm)
        path = path and convert_uri_template(path)
        for _, meth in ipairs(methods or {}) do
            local methname = assert(meth.id, "method name missing")
            local method = meth.name
            local request = meth.request and meth.request[1]
            local params = request and request.param
            local required_params, optional_params = get_params(params, required_prm, optional_prm)
            local expected_status
            for _, response in ipairs(meth.response or {}) do
                local status = response.status
                if status then
                    if not expected_status then
                        expected_status = {}
                    end
                    expected_status[#expected_status+1] = tonumber(status)
                end
            end
            spore.methods[methname] = {
                base_url = base_url,
                path = path,
                method = method,
                required_params = required_params,
                optional_params = optional_params,
                required_payload = (method == 'POST')
                                or (method == 'PUT')
                                or nil,
                expected_status = expected_status,
            }
        end
    end -- populate

    local function walk (resource, required_prm, optional_prm)
        for _, _resource in ipairs(resource or {}) do
            local required_params, optional_params = get_params({}, required_prm, optional_prm)
            walk(_resource.resource, required_params, optional_params)
            populate(_resource.method, _resource.path, required_params, optional_params)
        end
    end --walk

    for _, _resources in ipairs(wadl.resources or {}) do
        base_url = _resources.base
        walk(_resources.resource)
    end

    populate(wadl.method)

    return spore
end
m.convert = convert

function m.new_from_wadl (name, opts)
    opts = opts or {}
    checktype('new_from_wadl', 1, name, 'string')
    checktype('new_from_wadl', 2, opts, 'table')
    local content = slurp(name)
    return new_from_lua(convert(content), opts)
end

return m
--
-- Copyright (c) 2012-2018 Francois Perrad
--
-- This library is licensed under the terms of the MIT/X11 license,
-- like Lua itself.
--
