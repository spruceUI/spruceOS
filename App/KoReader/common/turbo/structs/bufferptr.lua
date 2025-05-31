-- Turbo.lua Buffer pointer implementation
--
-- Copyright 2014 John Abrahamsen
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

require 'turbo.3rdparty.middleclass'
local ffi = require "ffi"

local BufferPtr = class('BufferPtr')

function BufferPtr:initialize(ptr, size)
	assert(ptr ~= nil, "Null ptr given.")
	self.ptr = ptr
	self.size = size
end

function BufferPtr:len() return self.size end

function BufferPtr:get() return self.ptr, self.size end

return BufferPtr