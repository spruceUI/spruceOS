--- Turbo.lua Coroutine Context module
-- Tools to handle yielding of RequestHandlers and asynchronous requests.
-- Simple, yet effective.
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

require "turbo.3rdparty.middleclass"

local coctx = {} -- coctx namespace.

--- Couroutine context helper class.
-- This class is used to help tie yields in Turbo RequestHandlers together
-- with waiting for events to become available. The class act as a reference
-- for both the user and the IOLoop to tie suspended coroutines together with
-- actual async operations. Typical usage would be:
--
-- function MyHandler:get()
--     local response, error = coroutine.yield(
--          turbo.async.HTTPClient:new():fetch("http://myjson.org"))
--     .... do stuff with response when it is ready without blocking ....
-- end
--
-- The HTTPClient class function fetch returns a CoroutineContext instance.
-- The coroutine.yield will halt execution of the function and return the
-- CoroutineContext from 'fetch'.  The IOLoop will keep a reference to the
-- returned CoroutineContext together with the suspended coroutine. This list
-- is not iterated on every IOLoop iteration so it is relatively cheap to have
-- thousands of yielded RequestHandlers at once. When the HTTPClient class
-- internals has handled the request (or failed to do so), it will trigger a
-- coroutine resume with the parameters stored in the CoroutineContext via a
-- callback placed on the IOLoop by matching the CorutineContext by reference.
-- Only the IOLoop will know anything about suspended coroutines.
-- Lua Coroutines are not OS threads and are purely implemented in the Lua
-- interpreter, and as such are very cheap to create, suspend and destroy.
-- Yielding can be done from anywhere that the IOLoop:add_callback() has been
-- used to place a function on the IOLoop. However the yield must, either
-- return a CoroutineContext or a function. A yielded function will simply be
-- resumed on next iteration of the IOLoop. The yielder is free to yield again.
-- This class is NOT EXCEPTION/ERROR safe, and should not raise any errors as
-- they are unhandled, and will cause the program to exit!
coctx.CoroutineContext = class("CoroutineContext")

coctx.states = {
     SUSPENDED  = 0x0
    ,DEAD       = 0x1
    ,WORKING    = 0x2
    ,WAIT_COND  = 0x3
    ,SCHED      = 0x4
}

--- Initialize CoroutineContext class instance.
-- @param io_loop (IOLoop instance)
function coctx.CoroutineContext:initialize(io_loop)
    assert(io_loop, "No IOLoop class given to CoroutineContext.")
    self.co_args = {}
    self.co_state = coctx.states.SUSPENDED
    self.co_data = nil
    self.io_loop = io_loop
end

--- Set arguments to resume yielded context with.
-- @param args (Table or single type)
function coctx.CoroutineContext:set_arguments(args)
    if (type(args) == "table") then
        self.co_args = args
    else
        self.co_args[#self.co_args + 1] = args
    end
    return self
end

function coctx.CoroutineContext:set_state(state)
    self.co_state = state
    return self
end
function coctx.CoroutineContext:get_state(state)
    return self.co_state
end

function coctx.CoroutineContext:finalize_context()
    self.io_loop:finalize_coroutine_context(self)
end

function coctx.CoroutineContext:get_coroutine_arguments()
    return self.co_args
end

return coctx
