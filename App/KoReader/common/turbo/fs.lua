--- Turbo.lua file system Module
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

local ffi = require "ffi"
local syscall = require "turbo.syscall"

local fs = {}

--- File system constants
fs.NAME_MAX = 255
fs.PATH_MAX = 4096


--- Read out file metadata with a given path
function fs.stat(path, buf)
    local stat_t = ffi.typeof("struct stat")
    if not buf then buf = stat_t() end
    local ret = ffi.C.syscall(syscall.SYS_stat, path, buf)
    if ret == -1 then
        return -1, ffi.string(ffi.C.strerror(ffi.errno()))
    end
    return buf
end

--- Check whether a given path is directory
function fs.is_file(path)
    local buf, err = fs.stat(path, nil)
    if buf == -1 then return false, err end
    if bit.band(buf.st_mode, syscall.S_IFREG) == syscall.S_IFREG then
        return true
    else
        return false
    end
end

--- Check whether a given path is directory
function fs.is_dir(path)
    local buf, err = fs.stat(path, nil)
    if buf == -1 then return false, err end
    if bit.band(buf.st_mode, syscall.S_IFDIR) == syscall.S_IFDIR then
        return true
    else
        return false
    end
end

function fs.glob(pattern)
    local re = -1
    glob_t = ffi.new("glob_t[1]")
    re = ffi.C.glob(pattern, 0, nil, glob_t)
    if re ~= 0 then
        ffi.C.globfree(glob_t)
        return nil
    end

    local files = {}
    local i = 0
    while i < glob_t[0].gl_pathc do
        table.insert(files, ffi.string(glob_t[0].gl_pathv[i]))
        i = i + 1
    end
    ffi.C.globfree(glob_t)
    return files
end

return fs
