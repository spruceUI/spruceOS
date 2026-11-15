--- A dialog over the current screen: title, message, one or more buttons
---
--- modal.open({ title, message, buttons = { { label, onPress } ... }, cancel = index })
--- B presses the cancel button (the last one by default).
local theme = require("ui.theme")
local draw = require("ui.draw")

local modal = {}

local current = nil

function modal.open(opts)
	current = {
		title = opts.title or "",
		message = opts.message or "",
		buttons = opts.buttons or { { label = "OK" } },
		index = opts.focus or 1,
	}
	current.cancel = opts.cancel or #current.buttons
end

function modal.isOpen()
	return current ~= nil
end

function modal.close()
	current = nil
end

local function press(i)
	local button = current.buttons[i]
	current = nil
	if button and button.onPress then
		button.onPress()
	end
end

function modal.handle(action)
	if not current then
		return false
	end
	if action == "left" then
		current.index = math.max(1, current.index - 1)
	elseif action == "right" then
		current.index = math.min(#current.buttons, current.index + 1)
	elseif action == "a" then
		press(current.index)
	elseif action == "b" then
		press(current.cancel)
	end
	return true
end

function modal.draw()
	if not current then
		return
	end
	local c = theme.colors
	theme.setColor(c.scrim)
	love.graphics.rectangle("fill", 0, 0, theme.w, theme.h)
	local w = math.min(theme.w - theme.pad * 2, theme.px(500))
	local inner = w - theme.pad * 2
	local titleH = theme.fonts.bodyBold:getHeight()
	local _, lines = theme.fonts.small:getWrap(draw.clean(current.message), inner)
	local msgH = #lines * theme.fonts.small:getHeight()
	local buttonH = theme.px(36)
	local h = theme.pad * 3 + titleH + theme.gap + msgH + buttonH
	local x = math.floor((theme.w - w) / 2)
	local y = math.floor((theme.h - h) / 2)
	theme.setColor(c.surface)
	love.graphics.rectangle("fill", x, y, w, h, theme.radius, theme.radius)
	theme.setColor(c.outline)
	love.graphics.setLineWidth(1)
	love.graphics.rectangle("line", x, y, w, h, theme.radius, theme.radius)
	draw.text(theme.fonts.bodyBold, current.title, x + theme.pad, y + theme.pad, inner, c.text)
	draw.paragraph(theme.fonts.small, current.message, x + theme.pad, y + theme.pad + titleH + theme.gap, inner, c.textDim)

	local n = #current.buttons
	local bw = math.floor((inner - theme.gap * (n - 1)) / n)
	local by = y + h - theme.pad - buttonH
	for i, button in ipairs(current.buttons) do
		local bx = x + theme.pad + (i - 1) * (bw + theme.gap)
		local focused = i == current.index
		theme.setColor(focused and c.accent or c.surfaceFocus)
		love.graphics.rectangle("fill", bx, by, bw, buttonH, theme.radius, theme.radius)
		local f = theme.fonts.small
		draw.text(f, button.label, bx, by + (buttonH - f:getHeight()) / 2, bw, focused and c.onAccent or c.text, "center")
	end
end

return modal
