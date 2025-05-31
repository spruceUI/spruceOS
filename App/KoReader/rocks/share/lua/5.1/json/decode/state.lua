--[[
	Licensed according to the included 'LICENSE' document
	Author: Thomas Harning Jr <harningt@gmail.com>
]]

local setmetatable = setmetatable
local jsonutil = require("json.util")
local assert = assert
local type = type
local next = next
local unpack = require("table").unpack or unpack

local _ENV = nil

local state_ops = {}
local state_mt = {
	__index = state_ops
}

function state_ops.pop(self)
	self.previous_set = true
	self.previous = self.active
	local i = self.i
	-- Load in this array into the active item
	self.active = self.stack[i]
	self.active_state = self.state_stack[i]
	self.active_key = self.key_stack[i]
	self.stack[i] = nil
	self.state_stack[i] = nil
	self.key_stack[i] = nil

	self.i = i - 1
end

function state_ops.push(self)
	local i = self.i + 1
	self.i = i
	
	self.stack[i] = self.active
	self.state_stack[i] = self.active_state
	self.key_stack[i] = self.active_key
end

function state_ops.put_object_value(self, trailing)
	local object_options = self.options.object
	if trailing and object_options.trailingComma then
		if not self.active_key then
			return
		end
	end
	assert(self.active_key, "Missing key value")
	object_options.setObjectKey(self.active, self.active_key, self:grab_value(object_options.allowEmptyElement))
	self.active_key = nil
end

function state_ops.put_array_value(self, trailing)
	local array_options = self.options.array
	-- Safety check
	if trailing and not self.previous_set and array_options.trailingComma then
		return
	end
	local new_index = self.active_state + 1
	self.active_state = new_index
	self.active[new_index] = self:grab_value(array_options.allowEmptyElement)
end

function state_ops.put_call_value(self, trailing)
	local call_options = self.options.calls
	-- Safety check
	if trailing and not self.previous_set and call_options.trailingComma then
		return
	end
	local new_index = self.active_state + 1
	self.active_state = new_index
	self.active[new_index] = self:grab_value(call_options.allowEmptyElement)
end

function state_ops.put_value(self, trailing)
	if self.active_state == 'object' then
		self:put_object_value(trailing)
	elseif self.active.func then
		self:put_call_value(trailing)
	else
		self:put_array_value(trailing)
	end
end

function state_ops.new_array(self)
	local new_array = {}
	if jsonutil.InitArray then
		new_array = jsonutil.InitArray(new_array) or new_array
	end
	self.active = new_array
	self.active_state = 0
	self.active_key = nil
	self:unset_value()
end

function state_ops.end_array(self)
	if self.previous_set or self.active_state ~= 0 then
		-- Not an empty array
		self:put_value(true)
	end
	if self.active_state ~= #self.active then
		-- Store the length in
		self.active.n = self.active_state
	end
end

function state_ops.new_object(self)
	local new_object = {}
	self.active = new_object
	self.active_state = 'object'
	self.active_key = nil
	self:unset_value()
end

function state_ops.end_object(self)
	if self.active_key or self.previous_set or next(self.active) then
		-- Not an empty object
		self:put_value(true)
	end
end

function state_ops.new_call(self, name, func)
	-- TODO setup properly
	local new_call = {}
	new_call.name = name
	new_call.func = func
	self.active = new_call
	self.active_state = 0
	self.active_key = nil
	self:unset_value()
end

function state_ops.end_call(self)
	if self.previous_set or self.active_state ~= 0 then
		-- Not an empty array
		self:put_value(true)
	end
	if self.active_state ~= #self.active then
		-- Store the length in
		self.active.n = self.active_state
	end
	local func = self.active.func
	if func == true then
		func = jsonutil.buildCall
	end
	self.active = func(self.active.name, unpack(self.active, 1, self.active.n or #self.active))
end


function state_ops.unset_value(self)
	self.previous_set = false
	self.previous = nil
end

function state_ops.grab_value(self, allowEmptyValue)
	if not self.previous_set and allowEmptyValue then
		-- Calculate an appropriate empty-value
		return self.emptyValue
	end
	assert(self.previous_set, "Previous value not set")
	self.previous_set = false
	return self.previous
end

function state_ops.set_value(self, value)
	assert(not self.previous_set, "Value set when one already in slot")
	self.previous_set = true
	self.previous = value
end

function state_ops.set_key(self)
	assert(self.active_state == 'object', "Cannot set key on array")
	local value = self:grab_value()
	local value_type = type(value)
	if self.options.object.number then
		assert(value_type == 'string' or value_type == 'number', "As configured, a key must be a number or string") 
	else
		assert(value_type == 'string', "As configured, a key must be a string")
	end
	self.active_key = value
end


local function create(options)
	local emptyValue
	-- Calculate an empty value up front
	if options.others.allowUndefined then
		emptyValue = options.others.undefined or nil
	else
		emptyValue = options.others.null or nil
	end
	local ret = {
		options = options,
		stack = {},
		state_stack = {},
		key_stack = {},
		i = 0,
		active = nil,
		active_key = nil,
		previous = nil,
		active_state = nil,
		emptyValue = emptyValue
	}
	return setmetatable(ret, state_mt)
end

local state = {
	create = create
}

return state
