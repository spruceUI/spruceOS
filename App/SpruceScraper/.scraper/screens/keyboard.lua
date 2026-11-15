--- Text entry screen around ui/keyboard.lua
local Keyboard = require("ui.keyboard")

local screen = {}
local kb

function screen.enter(params)
	kb = Keyboard.new(params)
end

function screen.handle(action)
	kb:handle(action)
end

function screen.draw()
	kb:draw()
end

return screen
