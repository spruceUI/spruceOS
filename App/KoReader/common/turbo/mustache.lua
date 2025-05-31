--- Turbo.lua Mustache.js fast compiler.
-- Logic-less templates with {{ }}, http://mustache.github.io/
-- Turbo.lua has a small and very fast Mustache parser built-in. Mustache
-- templates are logic-less templates, which are supposed to help you keep
-- your business logic outside of templates and inside "controllers".
--
-- For more information on Mustache, please see this:
-- http://mustache.github.io/mustache.5.html
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

local util = require "turbo.util"
local escape = require "turbo.escape"
local buffer = require "turbo.structs.buffer"
local log = require "turbo.log"
local ffi = require "ffi"
local bit = jit and require "bit" or require "bit32"
require "turbo.3rdparty.middleclass"

local b = string.byte

local START =           "{{"
local START_NO_ESC =    "{{{"
local END =             "}}"
local END_NO_ESC =      "}}}"
local START_SEC =       '#'
local END_SEC =         '/'
local START_INV_SEC =   '^'
local COMMENT =         '!'
local ESCAPE =          '&'
local PARTIAL =         '>'

--- Mustache parser states.
local PNONE =           0x00
local PSTART =          0x01
local PSTARTNOESC =     0x02
local PSTARTSEC =       0x03
local PSTARTSECINV =    0x04
local PTABLEKEY =       0x05
local PTABLEKEYNOESC =  0x06
local PEND =            0x07
local PCOMMENT =        0x08
local PPARTIAL =        0x09

--- Template instruction set
local MSTR =            0x01    -- Constant string
local TKEY =            0x02    -- Table key
local TKEE =            0x22    -- Table key escape
local SECS =            0x03    -- Section straight
local SECI =            0x33    -- Section inverted
local SECE =            0x05    -- Section end
local PART =            0x06    -- Partial

local Mustache = {}

local function IS_WHITESPACE(char)
    if char == b ' ' or char == b '\t' then
        return true
    end
end

local function PLAIN_STRING(tbl, ptr, sz)
    tbl[#tbl+1]= {}
    tbl[#tbl][1] = MSTR
    tbl[#tbl][2] = ffi.string(ptr, sz)
end

local function TABLE_KEY(tbl, key, sz)
    tbl[#tbl+1] = {}
    tbl[#tbl][1] = TKEE
    tbl[#tbl][2] = ffi.string(key, sz)
end

local function TABLE_KEY_NO_ESC(tbl, key, sz)
    tbl[#tbl+1] = {}
    tbl[#tbl][1] = TKEY
    tbl[#tbl][2] = ffi.string(key, sz)
end


local function SECTION(tbl, key, sz)
    tbl[#tbl+1] = {}
    tbl[#tbl][1] = SECS
    tbl[#tbl][2] = ffi.string(key, sz)
end

local function SECTION_INVERTED(tbl, key, sz)
    tbl[#tbl+1] = {}
    tbl[#tbl][1] = SECI
    tbl[#tbl][2] = ffi.string(key, sz)
end

local function SECTION_END(tbl, key, sz)
    tbl[#tbl+1] = {}
    tbl[#tbl][1] = SECE
    tbl[#tbl][2] = ffi.string(key, sz)
end

local function SEARCH(h, hlen, n)
    return util.str_find(h, ffi.cast("char *", n), hlen, n:len())
end

local function PARTIAL_NAME(tbl, key, sz)
    tbl[#tbl+1] = {}
    tbl[#tbl][1] = PART
    tbl[#tbl][2] = ffi.string(key, sz)
end

local function CHECK_TABLE_SEC(tbl, key, sz)
    local name = ffi.string(key, sz)
    for i = #tbl, 1, -1 do
        if (tbl[i][1] == SECS or tbl[i][1] == SECI) and
            tbl[i][2] == name then
            return true
        end
    end
end

--- Compile a Mustache highlighted string into its intermediate state before
-- rendering. This function does some validation on the template. If it finds
-- syntax errors a error with a message is raised. It is always a good idea to
-- cache pre-compiled frequently used templates before rendering them. Although
-- compiling each time is usally not a big overhead.
-- @param template (String) Template in string form.
-- @return (Table) Parse table that can be used for Mustache.render.
function Mustache.compile(template)
    local vmtbl = {}
    local temp = ffi.cast("char*", template)
    local tsz = template:len()
    local consumed = 0
    local state = PNONE
    local mark

    -- Fast forward until mustaches is found.
    ::search::
    local loc = SEARCH(temp, tsz - consumed, START)
    if loc ~= nil then
        if loc[2] ~= b '{' then
            -- No escape mustache {{
            PLAIN_STRING(vmtbl, temp, loc - temp)
            state = PSTART
            consumed = consumed + (loc - temp) + START:len()
            temp = loc + START:len()
        else
            -- Escape mustache {{{
            PLAIN_STRING(vmtbl, temp, (loc - temp))
            state = PSTARTNOESC
            consumed = consumed + (loc - temp) + START_NO_ESC:len()
            temp = loc + START_NO_ESC:len()
        end
    else
        -- No mustaches or end of file reached.
        -- Add what is left.
        PLAIN_STRING(vmtbl, temp, tsz - consumed)
        if state ~= PNONE then
            error("Unclosed mustaches in template.")
        end
        goto ret
    end
    while consumed < tsz do
        if IS_WHITESPACE(temp[0]) then
            if state == PTABLEKEY then
                -- End of table key if whitespace directly after tablekey.
                TABLE_KEY(vmtbl, mark, (temp - mark))
                state = PNONE
            elseif state == PTABLEKEYNOESC then
                TABLE_KEY_NO_ESC(vmtbl, mark, (temp - mark))
                state = PNONE
            elseif state == PEND then
                -- Check if section end is actually opened somewhere.
                if not CHECK_TABLE_SEC(vmtbl, mark + 1, (temp - mark - 1)) then
                    error(string.format(
                        "Trying to end section '%s', but it was never opened.",
                    ffi.string(mark + 1, (temp - mark - 1))))
                end
                SECTION_END(vmtbl, mark + 1, (temp - mark - 1))
                state = PNONE
            elseif state == PSTARTSEC then
                SECTION(vmtbl, mark + 1, (temp - mark - 1))
                state = PNONE
            elseif state == PSTARTSECINV then
                SECTION_INVERTED(vmtbl, mark + 1, (temp - mark - 1))
                state = PNONE
            elseif state == PPARTIAL then
                if mark + 1 == temp then
                    mark = mark + 1
                else
                    PARTIAL_NAME(vmtbl, mark + 1, (temp - mark - 1))
                    state = PNONE
                end
            elseif state == PCOMMENT then
                state = PNONE
            end
            -- Whitespace is allowed if state is not above, just skip.
            -- Most probably it is something like {{ name }}
        elseif temp[0] == b '}' and temp[1] == b '}' then
            -- End of mustache highlight.
            -- Determine escapeness.
            if temp[2] == b '}'  then
                if state == PTABLEKEYNOESC then
                    -- No escape three mustache case "}}}".
                    TABLE_KEY_NO_ESC(vmtbl, mark, (temp - mark))
                    state = PNONE
                elseif state == PSTARTSEC then
                    -- Basically we do no treat unescaped list {{{#list}}} any
                    -- other way than {{#list}}
                    SECTION(vmtbl, mark + 1, (temp - mark - 1))
                    -- Skip magic character '#' from name.
                    state = PNONE
                elseif state == PEND then
                    -- Check if section end is actually opened somewhere.
                    if not CHECK_TABLE_SEC(vmtbl, mark + 1, (temp - mark - 1)) then
                        error(string.format(
                            "Trying to end section '%s', but it was never opened."),
                        ffi.string(mark + 1, (temp - mark - 1)))
                    end
                    SECTION_END(vmtbl, mark + 1, (temp - mark - 1))
                    state = PNONE
                elseif state == PSTARTSECINV then
                    SECTION_INVERTED(vmtbl, mark + 1, (temp - mark - 1))
                    state = PNONE
                elseif state == PPARTIAL then
                    PARTIAL_NAME(vmtbl, mark + 1, (temp - mark - 1))
                    state = PNONE
                elseif state == PCOMMENT then
                    -- Ignore comments.
                    state = PNONE
                end
                temp = temp + 3
                consumed = consumed + 3
            else
                if state == PTABLEKEY then
                    TABLE_KEY(vmtbl, mark, (temp - mark))
                    state = PNONE
                elseif state == PTABLEKEYNOESC then
                    -- {{ &key }} case.
                    TABLE_KEY_NO_ESC(vmtbl, mark + 1, (temp - mark - 1))
                    state = PNONE
                elseif state == PSTARTSEC then
                    SECTION(vmtbl, mark + 1, (temp - mark - 1))
                    state = PNONE
                elseif state == PEND then
                    if not CHECK_TABLE_SEC(vmtbl, mark + 1, (temp - mark - 1)) then
                        error(string.format(
                            "Trying to end section '%s', but it was never opened.",
                        ffi.string(mark + 1, (temp - mark - 1))))
                    end
                    SECTION_END(vmtbl, mark + 1, (temp - mark - 1))
                    state = PNONE
                elseif state == PSTARTSECINV then
                    SECTION_INVERTED(vmtbl, mark + 1, (temp - mark - 1))
                    state = PNONE
                elseif state == PPARTIAL then
                    PARTIAL_NAME(vmtbl, mark + 1, (temp - mark - 1))
                    state = PNONE
                elseif state == PCOMMENT then
                    state = PNONE
                end
                temp = temp + 2
                consumed = consumed + 2
            end
            goto search
        elseif state == PSTART  or state == PSTARTNOESC then
            -- Essentially next char is either first char of key or it is
            -- a section char "#". If a match is found a mark is placed.
            if temp[0] == b(START_SEC) then
                mark = temp
                state = PSTARTSEC
            elseif temp[0] == b(START_INV_SEC) then
                mark = temp
                state = PSTARTSECINV
            elseif temp[0] == b(END_SEC) then
                mark = temp
                state = PEND
            elseif temp[0] == b(ESCAPE) then
                mark = temp
                state = PTABLEKEYNOESC
            elseif temp[0] == b(COMMENT) then
                -- Comment statement, ignore.
                state = PCOMMENT
            elseif temp[0] == b(PARTIAL) then
                mark = temp
                state = PPARTIAL
            else
                -- No prefix, must be a table key.
                mark = temp
                if state == PSTART then
                    state = PTABLEKEY
                else
                    state = PTABLEKEYNOESC
                end
            end
        end
        consumed = consumed + 1
        temp = temp + 1
    end
    ::ret::
    return vmtbl
end

function Mustache._find_in_obj_parents(arg, obj_parents)
    for i = 1, #obj_parents do
        if obj_parents[i][arg] then
            return obj_parents[i][arg]
        end
    end
end

function Mustache._render_section(vmtbl, obj, i, safe, partials, obj_parents)
    local buf = buffer(1024)
    local secname = vmtbl[i][2]
    local inversed = vmtbl[i][1] == SECI
    local base_i = i
    for y = 1, #obj, 1 do
        -- Reset to base.
        i = base_i + 1
        while 1 do
            local instr = vmtbl[i][1]
            local arg = vmtbl[i][2]
            if instr == SECE and arg == secname then
                -- End of current section.
                break
            elseif instr == MSTR then
                buf:append_luastr_right(arg)
            elseif instr == TKEY then
                if type(obj[y]) == "table" and obj[y][arg] then
                    if type(obj[y][arg]) == "string" then
                        buf:append_luastr_right(obj[y][arg])
                    elseif type(obj[y][arg]) == "number" then
                        buf:append_luastr_right(tostring(obj[y][arg]))
                    elseif type(obj[y][arg]) == "function" then
                        -- May also be a function.
                        buf:append_luastr_right(obj[y][arg](arg) or "")
                    end
                else
                    local in_parent = Mustache._find_in_obj_parents(arg, obj_parents)
                    if in_parent then
                        if type(in_parent) == "string" then
                            buf:append_luastr_right(in_parent)
                        elseif type(in_parent) == "number" then
                            buf:append_luastr_right(tostring(in_parent))
                        elseif type(in_parent) == "function" then
                            -- May also be a function.
                            buf:append_luastr_right(in_parent(arg) or "")
                        end
                    elseif safe == true then
                        error(
                            string.format(
                                "Mustache.render, \
                                key should be table not %s index %d at: \r\n%s",
                                type(obj[y]),
                                y,
                                Mustache._template_dump(vmtbl, i)))
                    end
                end
            elseif instr == TKEE then
                if type(obj[y]) == "table" and obj[y][arg] then
                    if type(obj[y][arg]) == "string" then
                        buf:append_luastr_right(escape.html_escape(obj[y][arg]))
                    elseif type(obj[y][arg]) == "number" then
                        buf:append_luastr_right(tostring(obj[y][arg]))
                    elseif type(obj[y][arg]) == "function" then
                        -- May also be a function.
                        buf:append_luastr_right(
                            escape.html_escape(obj[y][arg](arg) or ""))
                    end
                else
                    local in_parent = Mustache._find_in_obj_parents(arg, obj_parents)
                    if in_parent then
                        if type(in_parent) == "string" then
                            buf:append_luastr_right(escape.html_escape(in_parent))
                        elseif type(in_parent) == "number" then
                            buf:append_luastr_right(tostring(in_parent))
                        elseif type(in_parent) == "function" then
                            -- May also be a function.
                            buf:append_luastr_right(
                                escape.html_escape(in_parent(arg)) or "")
                        end
                    elseif safe == true then
                        error(
                            string.format(
                                "Mustache.render, \
                                key should be table not %s index %d at: \r\n%s",
                                type(obj[y]),
                                y,
                                Mustache._template_dump(vmtbl, i)))
                    end
                end
            elseif instr == SECS then
                if obj[y][arg] then
                    if type(obj[y][arg]) == "table" and #obj[y][arg] ~= 0 then
                        -- Nested section
                        obj_parents[#obj_parents+1] = obj[y]
                        local secbuf, new_i =
                            Mustache._render_section(vmtbl,
                                            obj[y][arg],
                                            i,
                                            safe,
                                            partials,
                                            obj_parents)
                        i = new_i
                        buf:append_right(secbuf:get())
                    else
                        -- Section used as conditional.
                        -- Table key has evaluated as truthy.
                        -- Basically nothing needs to be done.
                    end
                else
                    -- Section is purely used as a conditional thing,
                    -- and no key is found in table.
                    -- Just fast-forward until SECE is found.
                    while 1 do
                        i = i + 1
                        if vmtbl[i][1] == SECE and vmtbl[i][2] == arg then
                            break
                        end
                    end
                end
            elseif instr == SECI then
                if obj[y][arg] then
                    -- Object exists in a "if not" condition.
                    -- Fast-forward towards SECE.
                    while 1 do
                        i = i + 1
                        if vmtbl[i][1] == SECE and vmtbl[i][2] == arg then
                            break
                        end
                    end
                end
            elseif instr == PART then
                -- The partial gets the same object context as we have.
                -- Either a template string or a pre-compiled parse table can be
                -- used as partial.
                if partials[arg] then
                    local partial = Mustache._render_partial(
                        type(partials[arg]) == "string" and
                            Mustache.compile(partials[arg]) or partials[arg],
                        obj[y],
                        obj_parents,
                        partials,
                        safe)
                    buf:append_luastr_right(partial)
                end
            end
            i = i + 1
        end
    end
    return buf, i
end


function Mustache._render_partial(vmtbl, obj, obj_parents, partials, safe)
    local buf = buffer(1024*2)
    local i = 1
    local vmtbl_sz = #vmtbl
    while 1 do
        ::start::
        if i == vmtbl_sz + 1 then
            break
        end
        local instr = vmtbl[i][1]
        local arg = vmtbl[i][2]
        local sec
        if instr == MSTR then
            buf:append_luastr_right(arg)
        elseif instr == TKEE then
            if obj[arg] then
                if type(obj[arg]) == "string" then
                    local esc = escape.html_escape(obj[arg])
                    buf:append_luastr_right(esc)
                elseif type(obj[arg]) == "number" then
                    buf:append_luastr_right(tostring(obj[arg]))
                end
            else
                local in_parent = Mustache._find_in_obj_parents(arg, obj_parents)
                    if in_parent then
                        if type(in_parent) == "string" then
                            buf:append_luastr_right(in_parent)
                        elseif type(in_parent) == "number" then
                            buf:append_luastr_right(tostring(in_parent))
                        elseif type(in_parent) == "function" then
                            -- May also be a function.
                            buf:append_luastr_right(in_parent(arg) or "")
                        end

                    elseif safe == true then
                        error(
                            string.format(
                                "Mustache.render, missing variable at: \r\n%s",
                                Mustache._template_dump(vmtbl, i)))
                    end
            end
        elseif instr == TKEY then
            if obj[arg] then
                if type(obj[arg]) == "string" then
                    buf:append_luastr_right(obj[arg])
                end
            else
                local in_parent = Mustache._find_in_obj_parents(arg, obj_parents)
                if in_parent then
                    if type(in_parent) == "string" then
                        buf:append_luastr_right(in_parent)
                    elseif type(in_parent) == "number" then
                        buf:append_luastr_right(tostring(in_parent))
                    elseif type(in_parent) == "function" then
                        -- May also be a function.
                        buf:append_luastr_right(in_parent(arg) or "")
                    end
                elseif safe == true then
                    error(
                        string.format(
                            "Mustache.render, missing variable at: \r\n%s",
                            Mustache._template_dump(vmtbl, i)))
                end
            end
        elseif instr == SECS then
            if obj[arg] then
                if type(obj[arg]) == "table" and #obj[arg] ~= 0 then
                    local secbuf, new_i = Mustache._render_section(vmtbl,
                                                          obj[arg],
                                                          i,
                                                          safe,
                                                          partials,
                                                          {obj})
                    i = new_i
                    buf:append_right(secbuf:get())
                else
                    -- Section used as conditional.
                    -- Table key has evaluated as truthy.
                    -- Basically nothing needs to be done, except handle the
                    -- SECE.
                end
            else
                -- Section is purely used as a conditional thing, and no key is
                -- found in table.
                -- Just fast-forward until SECE is found.
                while 1 do
                    i = i + 1
                    if vmtbl[i][1] == SECE then
                        goto start
                    end
                end
            end
        elseif instr == SECI then
            if obj[arg] then
                -- Object exists in a "if not" condition.
                -- Fast-forward towards SECE.
                while 1 do
                    i = i + 1
                    if vmtbl[i][1] == SECE then
                        goto start
                    end
                end
            else
                -- Do nothing and continue run.
            end
        elseif instr == PART then
            if partials[arg] then
                local partial = Mustache._render_partial(
                    type(partials[arg]) == "string" and
                        Mustache.compile(partials[arg]) or partials[arg],
                    obj,
                    obj_parents,
                    partials,
                    allow_blank)
                buf:append_luastr_right(partial)
            end
        end
        i = i + 1
    end
    return tostring(buf)
end

function Mustache._render_template(vmtbl, obj, partials, safe)
    local buf = buffer(1024*2)
    local i = 1
    local vmtbl_sz = #vmtbl
    while 1 do
        ::start::
        if i == vmtbl_sz + 1 then
            break
        end
        local instr = vmtbl[i][1]
        local arg = vmtbl[i][2]
        local sec
        if instr == MSTR then
            buf:append_luastr_right(arg)
        elseif instr == TKEE then
            if obj[arg] then
                if type(obj[arg]) == "string" then
                    local esc = escape.html_escape(obj[arg])
                    buf:append_luastr_right(esc)
                elseif type(obj[arg]) == "number" then
                    buf:append_luastr_right(tostring(obj[arg]))
                end
            elseif safe == true then
                error(
                    string.format(
                        "Mustache.render, missing variable at: \r\n%s",
                        Mustache._template_dump(vmtbl, i)))
            end
        elseif instr == TKEY then
            if obj[arg] then
                if type(obj[arg]) == "string" then
                    buf:append_luastr_right(obj[arg])
                end
            elseif safe == true then
                error(
                    string.format(
                        "Mustache.render, missing variable at: \r\n%s",
                        Mustache._template_dump(vmtbl, i)))
            end
        elseif instr == SECS then
            if obj[arg] then
                if type(obj[arg]) == "table" and #obj[arg] ~= 0 then
                    local secbuf, new_i = Mustache._render_section(vmtbl,
                                                          obj[arg],
                                                          i,
                                                          safe,
                                                          partials,
                                                          {obj})
                    i = new_i
                    buf:append_right(secbuf:get())
                else
                    -- Section used as conditional.
                    -- Table key has evaluated as truthy.
                    -- Basically nothing needs to be done, except handle the
                    -- SECE.
                end
            else
                -- Section is purely used as a conditional thing, and no key is
                -- found in table.
                -- Just fast-forward until SECE is found.
                while 1 do
                    i = i + 1
                    if vmtbl[i][1] == SECE and vmtbl[i][2] == arg then
                        goto start
                    end
                end
            end
        elseif instr == SECI then
            if obj[arg] then
                -- Object exists in a "if not" condition.
                -- Fast-forward towards SECE.
                while 1 do
                    i = i + 1
                    if vmtbl[i][1] == SECE and vmtbl[i][2] == arg then
                        goto start
                    end
                end
            else
                -- Do nothing and continue run.
            end
        elseif instr == PART then
            -- The partial gets the same object context as we have.
            -- Either a template string or a pre-compiled parse table can be
            -- used as partial.
            if partials[arg] then
                local partial = Mustache.render(partials[arg],
                                                obj,
                                                partials,
                                                allow_blank)

                buf:append_luastr_right(partial)
            end
        end
        i = i + 1
    end
    return tostring(buf)
end

--- Render a template. Accepts a parse table compiled by Mustache.compile
-- or a uncompiled string. Obj is the table with keys.
-- @param allow_blank Halt with error if key does not exist in object table.
function Mustache.render(template, obj, partials, allow_blank)
    if not template then
        error("No precompiled template or template string passed to Mustache.render.")
    end
    if type(template) == "string" then
        template = Mustache.compile(template)
    elseif type(template) ~= "table" then
        error("Invalid template passed to Mustache.render")
    end
    if type(obj) ~= "table" then
        error("No table passed to Mustache.render")
    end
    return Mustache._render_template(template, obj, partials, allow_blank)
end

function Mustache._template_dump(tbl, mark)
    local dmp = ""
    local vmcode = {
        [0x1] =     "MSTR",
        [0x2] =     "TKEY",
        [0x22] =    "TKEE",
        [0x3] =     "SECS",
        [0x33] =    "SECI",
        [0x05] =    "SECE",
        [0x06] =    "PART",
        [0x066] =   "PANE"
    }
    dmp = dmp.."\
          ====================================\n"
    for i = 1, #tbl do
        if tbl[i][1] == SECS or tbl[i][1] == SECI or
            tbl[i][1] == SECE then
            dmp = dmp ..
                string.format("  0x%s \x1b[32m %s => \x1b[37m %s\n",
                    bit.tohex(i),
                    vmcode[tbl[i][1]],
                    tbl[i][2]:gsub("[\n\t]+", ""))
        elseif tbl[i][1] == TKEY or tbl[i][1] == TKEE then
            dmp = dmp ..
                string.format("  0x%s \x1b[32m %s => \x1b[37m %s\n",
                    bit.tohex(i),
                    vmcode[tbl[i][1]],
                    tbl[i][2]:gsub("[\n\t]+", ""))
        elseif tbl[i][1] == PART then
            dmp = dmp ..
                string.format("  0x%s \x1b[35m %s => \x1b[37m %s\n",
                    bit.tohex(i),
                    vmcode[tbl[i][1]],
                    tbl[i][2]:gsub("[\n\t]+", ""))
        else
            dmp = dmp ..
                string.format("  0x%s \x1b[36m %s => \x1b[37m '%s'\n",
                    bit.tohex(i),
                    vmcode[tbl[i][1]],
                    tbl[i][2]:gsub("[\n\t]+", ""))
        end
        if i == mark then
            dmp = dmp ..
                "              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n"
            return dmp
        end
    end
    dmp = dmp .. "              ====================================\n"
    return dmp
end

Mustache.TemplateHelper = class("TemplateHelper")

function Mustache.TemplateHelper:initialize(path)
    self.templates = {}
    self:set_base_directory(path)
end

function Mustache.TemplateHelper:set_base_directory(file)
    if type(file) ~= "string" then
        error("argument #1 is not a string.")
    elseif #file == 0 then
        error("argument #1 empty string.")
    elseif file:sub(#file) ~= "/" then
        file = file .. "/"
    end
    self.base_dir = file
end

function Mustache.TemplateHelper:load(template)
    if not template then
        error("No template name specified.")
    elseif not self.base_dir then
        error("Please call set_base_directory first.")
    end
    if self.templates[template] then
        return self.templates[template]
    else
        local data = util.read_all(self.base_dir .. template)
        local tbl = Mustache.compile(data)
        self.templates[template] = tbl
        return tbl
    end
end

function Mustache.TemplateHelper:render(template, table, partials, allow_blank)
    if type(template) == "string" then
        local compiled_tmpl = self:load(template)
        if not compiled_tmpl then
            error("Could not load template " .. template)
        end
        return Mustache.render(compiled_tmpl,
                               table or {},
                               partials,
                               allow_blank)
    end
    return Mustache.render(template, table or {}, partials, allow_blank)
end

return Mustache
