--- Buttons -> actions, polled once per frame, with repeat on held directions
---
--- Polling (rather than gamepadpressed callbacks) is what Aesthetic Spruce runs on every
--- supported device. Keyboard keys mirror the pad for desktop runs.
local layout = require("gamepad_layout")

local input = {}

local MAP = {
	up = { pad = { "dpup" }, keys = { "up" } },
	down = { pad = { "dpdown" }, keys = { "down" } },
	left = { pad = { "dpleft" }, keys = { "left" } },
	right = { pad = { "dpright" }, keys = { "right" } },
	a = { pad = { "a" }, keys = { "z", "return" } },
	b = { pad = { "b" }, keys = { "x", "backspace" } },
	x = { pad = { "x" }, keys = { "a" } },
	y = { pad = { "y" }, keys = { "s" } },
	l1 = { pad = { "leftshoulder" }, keys = { "q", "pageup" } },
	r1 = { pad = { "rightshoulder" }, keys = { "w", "pagedown" } },
	start = { pad = { "start" }, keys = { "space" } },
	select = { pad = { "back" }, keys = { "tab" } },
}

local REPEATS = { up = true, down = true, left = true, right = true, l1 = true, r1 = true }
local DELAY, INTERVAL = 0.35, 0.08

local held = {}
local timers = {}
local queue = {}
local injected = {}

local function isDown(action)
	if injected[action] then
		return true
	end
	local m = MAP[action]
	for _, key in ipairs(m.keys) do
		if love.keyboard.isDown(key) then
			return true
		end
	end
	for _, joy in ipairs(love.joystick.getJoysticks()) do
		if joy:isGamepad() then
			for _, button in ipairs(m.pad) do
				if joy:isGamepadDown(layout.sdlButton(button)) then
					return true
				end
			end
		end
	end
	return false
end

function input.update(dt)
	queue = {}
	for action in pairs(MAP) do
		local down = isDown(action)
		if down and not held[action] then
			queue[#queue + 1] = action
			timers[action] = DELAY
		elseif down and REPEATS[action] then
			timers[action] = timers[action] - dt
			if timers[action] <= 0 then
				timers[action] = INTERVAL
				queue[#queue + 1] = action
			end
		end
		held[action] = down
	end
	injected = {}
end

--- Actions that fired this frame, in no particular order
function input.pressed()
	return queue
end

--- Press an action for one frame (autorun and screenshot hooks)
function input.inject(action)
	injected[action] = true
end

return input
