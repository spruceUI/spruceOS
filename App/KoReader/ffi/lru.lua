-- lua-lru, LRU cache in Lua
-- Copyright (c) 2015 Boris Nagaev
-- See https://github.com/starius/lua-lru/blob/master/LICENSE for terms of use.

-- NOTE: This is https://github.com/starius/lua-lru, imported @ c559e249f0c6bc8ba33bcb0f40aa92bf65e58d9f
--       With a few minor modifications to account for our existing API.
--       LuaJIT seems to be able to do some serious magic with this,
--       but another contender could be https://github.com/openresty/lua-resty-lrucache/blob/master/lib/resty/lrucache/pureffi.lua
--       It's more complex, and doesn't fit quite as nicely in our existing APIs, though.

local lru = {}

function lru.new(max_size, max_bytes, enable_eviction_cb)

    assert(max_size >= 1, "max_size must be >= 1")
    assert(not max_bytes or max_bytes >= 1,
        "max_bytes must be >= 1")

    -- current size
    local size = 0
    local bytes_used = 0

    -- map is a hash map from keys to tuples
    -- tuple: value, prev, next, key
    -- prev and next are pointers to tuples
    local map = {}

    -- indices of tuple
    local VALUE = 1
    local PREV = 2
    local NEXT = 3
    local KEY = 4
    local BYTES = 5

    -- newest and oldest are ends of double-linked list
    local newest = nil -- first
    local oldest = nil -- last

    local removed_tuple -- created in del(), removed in set()

    -- remove a tuple from linked list
    local function cut(tuple)
        local tuple_prev = tuple[PREV]
        local tuple_next = tuple[NEXT]
        tuple[PREV] = nil
        tuple[NEXT] = nil
        if tuple_prev and tuple_next then
            tuple_prev[NEXT] = tuple_next
            tuple_next[PREV] = tuple_prev
        elseif tuple_prev then
            -- tuple is the oldest element
            tuple_prev[NEXT] = nil
            oldest = tuple_prev
        elseif tuple_next then
            -- tuple is the newest element
            tuple_next[PREV] = nil
            newest = tuple_next
        else
            -- tuple is the only element
            newest = nil
            oldest = nil
        end
    end

    -- insert a tuple to the newest end
    local function setNewest(tuple)
        if not newest then
            newest = tuple
            oldest = tuple
        else
            tuple[NEXT] = newest
            newest[PREV] = tuple
            newest = tuple
        end
    end

    local del
    if enable_eviction_cb then
        if max_bytes then
            del = function(key, tuple)
                tuple[VALUE]:onFree()
                map[key] = nil
                cut(tuple)
                size = size - 1
                bytes_used = bytes_used - tuple[BYTES]
                removed_tuple = tuple
            end
        else
            del = function(key, tuple)
                tuple[VALUE]:onFree()
                map[key] = nil
                cut(tuple)
                size = size - 1
                removed_tuple = tuple
            end
        end
    else
        if max_bytes then
            del = function(key, tuple)
                map[key] = nil
                cut(tuple)
                size = size - 1
                bytes_used = bytes_used - tuple[BYTES]
                removed_tuple = tuple
            end
        else
            del = function(key, tuple)
                map[key] = nil
                cut(tuple)
                size = size - 1
                removed_tuple = tuple
            end
        end
    end

    -- removes elements to provide enough memory
    -- returns last removed element or nil
    local makeFreeSpace
    if max_bytes then
        makeFreeSpace = function(bytes)
            while size + 1 > max_size or bytes_used + bytes > max_bytes do
                assert(oldest, "not enough storage for cache")
                del(oldest[KEY], oldest)
            end
        end
    else
        makeFreeSpace = function()
            while size + 1 > max_size do
                assert(oldest, "not enough storage for cache")
                del(oldest[KEY], oldest)
            end
        end
    end

    local function clear()
        while size > 0 do
            del(oldest[KEY], oldest)
        end
        removed_tuple = nil
    end

    local function chop()
        local half = size / 2
        while size > half do
            del(oldest[KEY], oldest)
        end
    end

    local function get(_, key)
        local tuple = map[key]
        if not tuple then
            return nil
        end
        cut(tuple)
        setNewest(tuple)
        return tuple[VALUE]
    end

    local set
    if max_bytes then
        set = function(_, key, value, bytes)
            local tuple = map[key]
            if tuple then
                del(key, tuple)
            end
            if value ~= nil then
                -- the value is not removed
                makeFreeSpace(bytes)
                local tuple1 = removed_tuple or {}
                map[key] = tuple1
                tuple1[VALUE] = value
                tuple1[KEY] = key
                tuple1[BYTES] = bytes
                size = size + 1
                bytes_used = bytes_used + bytes
                setNewest(tuple1)
            else
                assert(key ~= nil, "Key may not be nil")
            end
            removed_tuple = nil
        end
    else
        set = function(_, key, value)
            local tuple = map[key]
            if tuple then
                del(key, tuple)
            end
            if value ~= nil then
                -- the value is not removed
                makeFreeSpace()
                local tuple1 = removed_tuple or {}
                map[key] = tuple1
                tuple1[VALUE] = value
                tuple1[KEY] = key
                size = size + 1
                setNewest(tuple1)
            else
                assert(key ~= nil, "Key may not be nil")
            end
            removed_tuple = nil
        end
    end

    local function delete(_, key)
        return set(_, key, nil)
    end

    local function mynext(_, prev_key)
        local tuple
        if prev_key then
            tuple = map[prev_key][NEXT]
        else
            tuple = newest
        end
        if tuple then
            return tuple[KEY], tuple[VALUE]
        else
            return nil
        end
    end

    -- returns iterator for keys and values
    local function lru_pairs()
        return mynext, nil, nil
    end

    -- KOReader
    local function used_slots()
        return size
    end

    -- KOReader
    local function used_size()
        return bytes_used
    end

    -- KOReader
    local function total_slots()
        return max_size
    end

    -- KOReader
    local function total_size()
        return max_bytes
    end

    -- KOReader
    local function resize_slots(_, new_size)
        if new_size > max_size then
            max_size = new_size
        elseif new_size < max_size then
            while size > new_size do
                del(oldest[KEY], oldest)
            end
            max_size = new_size
        else
            return
        end
    end

    -- KOReader
    local resize_bytes
    if max_bytes then
        resize_bytes = function(_, new_bytes)
            if new_bytes > max_bytes then
                max_bytes = new_bytes
            elseif new_bytes < max_bytes then
                while bytes_used > new_bytes do
                    del(oldest[KEY], oldest)
                end
                max_bytes = new_bytes
            else
                return
            end
        end
    else
        resize_bytes = function()
            error("Cannot resize a slot-bound cache")
        end
    end

    local mt = {
        __index = {
            get = get,
            set = set,
            delete = delete,
            pairs = lru_pairs,
            clear = clear,
            chop = chop,
            used_slots = used_slots,
            used_size = used_size,
            total_slots = total_slots,
            total_size = total_size,
            resize_slots = resize_slots,
            resize_bytes = resize_bytes,
        },
        __pairs = lru_pairs,
    }

    return setmetatable({}, mt)
end

return lru
