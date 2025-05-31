--- Turbo.lua Turbovisor, auto-reload of application on file changes.
--
-- Copyright 2013 John Abrahamsen, Deyuan Deng
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
local bit = require "bit"
local turbo = require "turbo"
local fs = require "turbo.fs"

if not turbo.platform.__LINUX__ then
    error("Turbovisor is only supported on Linux.")
end

--- Parsing arguments for turbovisor
-- @param arg All command line input. Note arg[0] is 'turbovisor', arg[1] is
--    application name; so user-defined argument starts from arg[2]
-- @return a table containing option/value pair, options including:
--    'watch': set of files or directories to watch
--    'ignore': set of files or directories that turbovisor shouldn't watch
local function get_param(arg)
    local arg_opt
    local arg_tbl = {}
    for i = 2, #arg, 1 do
        if arg[i] == '--watch' or arg[i] == '-w' then
            arg_tbl.watch = arg_tbl.watch or {}
            arg_opt = 'watch'
        elseif arg[i] == '--ignore' or arg[i] == '-i' then
            arg_tbl.ignore = arg_tbl.ignore or {}
            arg_opt = 'ignore'
        else
            if string.sub(arg[i], 1, 2) == "./" then
                arg[i] = string.sub(arg[i], 3) -- pass './'
            end
            local files = fs.glob(arg[i])
            -- insert glob expanded result into table
            if files then
                for _,v in ipairs(files) do
                    table.insert(arg_tbl[arg_opt], v)
                end
            end
        end
    end
    -- Deal with default parameters
    if arg_tbl.watch == nil then arg_tbl.watch = {'.'} end
    return arg_tbl;
end


--- Kill all descendants for a given pid
local function kill_tree(pid)
    local file_handle = io.popen('pkill -P ' .. pid)
    file_handle:close()
end


--- The turbovisor class is a supervisor for detecting file changes
-- and restart supervised application.
local turbovisor = class("turbovisor", turbo.ioloop.IOLoop)

--- Start supervising.
function turbovisor:supervise()
    -- Get command line parameters
    self.arg_tbl = get_param(arg)
    -- Create a new inotify
    self.i_fd = turbo.inotify:new()
    -- Create a buffer for reading event in callback handler
    self.buf = ffi.gc(ffi.C.malloc(turbo.fs.PATH_MAX), ffi.C.free)
    -- Initialize ioloop, add inotify handler
    self:initialize()
    self:add_handler(self.i_fd, turbo.ioloop.READ, self.restart, self)
    -- Set watch on target file or directory
    for i, target in pairs(self.arg_tbl.watch) do
        if turbo.fs.is_dir(target) then
            turbo.inotify:watch_all(target, self.arg_tbl.ignore)
        else
            turbo.inotify:watch_file(target)
        end
    end
    -- Parameters for starting application
    local para = ffi.new("const char *[?]", 3)
    para[0] = "luajit"
    para[1] = arg[1]
    para[2] = nil
    self.para = ffi.cast("char *const*", para)
    -- Run application and supervisor
    local cpid = ffi.C.fork()
    if cpid == 0 then
        turbo.inotify:close()
        ffi.C.execvp("luajit", self.para)
        error(ffi.string(ffi.C.strerror(ffi.errno())))
    else
        self:start()
    end
end

--- Callback handler when files changed
-- For now, just restart the only one application
function turbovisor.restart(self, fd, events)
    -- Read out event
    ffi.C.read(fd, self.buf, turbo.fs.PATH_MAX);
    self.buf = ffi.cast("struct inotify_event*", self.buf)
    local full_path
    if self.buf.len == 0 then -- 'len = 0' if we watch on file directly
        full_path = turbo.inotify:get_watched_file(self.buf.wd)
    else
        local path = turbo.inotify:get_watched_file(self.buf.wd)
        full_path = path .. '/' .. ffi.string(self.buf.name)
        if path == '.' then full_path = ffi.string(self.buf.name) end
    end

    turbo.inotify:rewatch_if_ignored(self.buf, full_path)

    -- Simply return if we need to ignore the file
    if turbo.util.is_in(full_path, self.arg_tbl.ignore) then
        return
    end
    turbo.log.notice("[turbovisor.lua] File '" .. full_path ..
                         "' changed, application restarted!")
    -- Restart application
    kill_tree(ffi.C.getpid())
    local cpid = ffi.C.fork()
    if cpid == 0 then
        turbo.inotify:close()
        ffi.C.execvp("luajit", self.para)
        error(ffi.string(ffi.C.strerror(ffi.errno())))
    end
end

return turbovisor
