--- Turbo.lua syscall Module
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
-- modes

local ffi = require "ffi"
local platform = require "turbo.platform"
local util = require "turbo.util"
local tm = util.tablemerge
local octal = function (s) return tonumber(s, 8) end

local flags = {
    O_DIRECTORY = octal('0200000'),
    O_NOFOLLOW  = octal('0400000'),
    O_DIRECT    = octal('040000'),
    S_IFMT   = octal('0170000'),
    S_IFSOCK = octal('0140000'),
    S_IFLNK  = octal('0120000'),
    S_IFREG  = octal('0100000'),
    S_IFBLK  = octal('0060000'),
    S_IFDIR  = octal('0040000'),
    S_IFCHR  = octal('0020000'),
    S_IFIFO  = octal('0010000'),
    S_ISUID  = octal('0004000'),
    S_ISGID  = octal('0002000'),
    S_ISVTX  = octal('0001000'),
    S_IRWXU = octal('00700'),
    S_IRUSR = octal('00400'),
    S_IWUSR = octal('00200'),
    S_IXUSR = octal('00100'),
    S_IRWXG = octal('00070'),
    S_IRGRP = octal('00040'),
    S_IWGRP = octal('00020'),
    S_IXGRP = octal('00010'),
    S_IRWXO = octal('00007'),
    S_IROTH = octal('00004'),
    S_IWOTH = octal('00002'),
    S_IXOTH = octal('00001')
}

local cmds
--- ******* syscalls *******
if platform.__DARWIN__ then
    cmds = {
        SYS_stat             = 338,
        SYS_fstat            = 339,
        SYS_lstat            = 340
    }
elseif ffi.arch == "x86" then
    cmds = {
        SYS_stat             = 106,
        SYS_fstat            = 108,
        SYS_lstat            = 107,
        SYS_getdents         = 141,
        SYS_io_setup         = 245,
        SYS_io_destroy       = 246,
        SYS_io_getevents     = 247,
        SYS_io_submit        = 248,
        SYS_io_cancel        = 249,
        SYS_clock_settime    = 264,
        SYS_clock_gettime    = 265,
        SYS_clock_getres     = 266,
        SYS_clock_nanosleep  = 267
    }
elseif ffi.arch == "x64" then
    cmds = {
        SYS_stat             = 4,
        SYS_fstat            = 5,
        SYS_lstat            = 6,
        SYS_getdents         = 78,
        SYS_io_setup         = 206,
        SYS_io_destroy       = 207,
        SYS_io_getevents     = 208,
        SYS_io_submit        = 209,
        SYS_io_cancel        = 210,
        SYS_clock_settime    = 227,
        SYS_clock_gettime    = 228,
        SYS_clock_getres     = 229,
        SYS_clock_nanosleep  = 230
    }
elseif ffi.arch == "ppc" or ffi.arch == "ppc64le" then
    cmds = {
        SYS_stat             = 106,
        SYS_fstat            = 108,
        SYS_lstat            = 107,
        SYS_getdents         = 141,
        SYS_io_setup         = 227,
        SYS_io_destroy       = 228,
        SYS_io_getevents     = 229,
        SYS_io_submit        = 230,
        SYS_io_cancel        = 231,
        SYS_clock_settime    = 245,
        SYS_clock_gettime    = 246,
        SYS_clock_getres     = 247,
        SYS_clock_nanosleep  = 248
    }
elseif ffi.arch == "arm" then
    cmds = {
        SYS_stat             = 106,
        SYS_fstat            = 108,
        SYS_lstat            = 107,
        SYS_getdents         = 141,
        SYS_io_setup         = 243,
        SYS_io_destroy       = 244,
        SYS_io_getevents     = 245,
        SYS_io_submit        = 246,
        SYS_io_cancel        = 247,
        SYS_clock_settime    = 262,
        SYS_clock_gettime    = 263,
        SYS_clock_getres     = 264,
        SYS_clock_nanosleep  = 265
    }
elseif ffi.arch == "mipsel" then
    cmds = {
        SYS_stat             = 4106,
        SYS_fstat            = 4108,
        SYS_lstat            = 4107,
        SYS_getdents         = 4141,
        SYS_io_setup         = 4241,
        SYS_io_destroy       = 4242,
        SYS_io_getevents     = 4244,
        SYS_io_submit        = 4246,
        SYS_io_cancel        = 4245,
        SYS_clock_settime    = 4262,
        SYS_clock_gettime    = 4263,
        SYS_clock_getres     = 4264,
        SYS_clock_nanosleep  = 4265
    }
end

return tm(flags, cmds)
