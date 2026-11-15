--- Scrolling menu list
---
--- item fields (values may be functions of the item):
---   label, value, detail       text; detail is a second, smaller line
---   kind                       "action" (A runs onPress), "choice" (left/right run onChange),
---                              "toggle" (A or left/right flip checked), "info" (not focusable)
---   checked                    toggles: current state
---   disabled                   shown dimmed; A and left/right do nothing
---   onPress(item), onChange(item, dir)
local theme = require("ui.theme")
local draw = require("ui.draw")

local List = {}
List.__index = List

local function get(v, item)
	if type(v) == "function" then
		return v(item)
	end
	return v
end

function List.new(opts)
	local self = setmetatable({}, List)
	self.x = opts.x or 0
	self.y = opts.y or theme.headerH
	self.w = opts.w or theme.w
	self.h = opts.h or (theme.h - theme.headerH - theme.footerH)
	self.twoLine = opts.twoLine or false
	self.rowH = opts.rowH or (self.twoLine and theme.px(58) or theme.rowH)
	self.index = 1
	self.top = 1
	self:setItems(opts.items or {})
	return self
end

function List:setItems(items)
	self.items = items
	self:clamp()
end

function List:focusable(i)
	local item = self.items[i]
	return item ~= nil and item.kind ~= "info"
end

function List:clamp()
	if #self.items == 0 then
		self.index = 1
		return
	end
	self.index = math.max(1, math.min(self.index, #self.items))
	if not self:focusable(self.index) then
		for i = 1, #self.items do
			if self:focusable(i) then
				self.index = i
				break
			end
		end
	end
end

function List:current()
	return self.items[self.index]
end

function List:visibleRows()
	return math.max(1, math.floor(self.h / self.rowH))
end

function List:move(delta, wrap)
	local n = #self.items
	if n == 0 then
		return
	end
	local i = self.index
	for _ = 1, n do
		i = i + delta
		if i < 1 then
			if not wrap then
				return
			end
			i = n
		elseif i > n then
			if not wrap then
				return
			end
			i = 1
		end
		if self:focusable(i) then
			self.index = i
			return
		end
	end
end

function List:page(delta)
	local target = math.max(1, math.min(#self.items, self.index + delta * self:visibleRows()))
	self.index = target
	if not self:focusable(target) then
		self:move(delta > 0 and 1 or -1)
	end
end

function List:handle(action)
	local item = self:current()
	if action == "up" then
		self:move(-1, true)
	elseif action == "down" then
		self:move(1, true)
	elseif action == "l1" then
		self:page(-1)
	elseif action == "r1" then
		self:page(1)
	elseif item and not get(item.disabled, item) then
		if action == "a" then
			if item.kind == "toggle" and item.onChange then
				item.onChange(item, 1)
			elseif item.onPress then
				item.onPress(item)
			elseif item.kind == "choice" and item.onChange then
				item.onChange(item, 1)
			end
		elseif (action == "left" or action == "right") and item.onChange
			and (item.kind == "choice" or item.kind == "toggle") then
			item.onChange(item, action == "left" and -1 or 1)
		else
			return false
		end
	else
		return false
	end
	return true
end

local function drawCheck(x, y, size, on, dim)
	local c = theme.colors
	theme.setColor(dim and c.disabled or (on and c.accent or c.subtext))
	love.graphics.setLineWidth(math.max(1, theme.px(2)))
	love.graphics.rectangle(on and "fill" or "line", x, y, size, size, theme.px(4), theme.px(4))
	if on then
		theme.setColor(c.onAccent)
		local s = size
		love.graphics.line(x + s * 0.22, y + s * 0.52, x + s * 0.42, y + s * 0.72, x + s * 0.78, y + s * 0.3)
	end
end

function List:draw()
	local rows = self:visibleRows()
	if self.index < self.top then
		self.top = self.index
	elseif self.index > self.top + rows - 1 then
		self.top = self.index - rows + 1
	end
	self.top = math.max(1, math.min(self.top, math.max(1, #self.items - rows + 1)))

	local c = theme.colors
	local pad = theme.pad
	love.graphics.push("all")
	love.graphics.setScissor(self.x, self.y, self.w, self.h)
	for i = self.top, math.min(#self.items, self.top + rows - 1) do
		local item = self.items[i]
		local y = self.y + (i - self.top) * self.rowH
		local focused = i == self.index
		local disabled = get(item.disabled, item)
		local rx, rw = self.x + pad / 2, self.w - pad
		if focused then
			theme.setColor(c.surfaceFocus)
			love.graphics.rectangle("fill", rx, y + 2, rw, self.rowH - 4, theme.radius, theme.radius)
			theme.setColor(c.accent)
			love.graphics.rectangle("fill", rx, y + self.rowH * 0.25, theme.px(4), self.rowH * 0.5, 2, 2)
		end
		local labelColor = item.kind == "info" and c.subtext or (disabled and c.disabled or c.text)
		local font = item.kind == "info" and theme.fonts.small or theme.fonts.body
		local valueW = 0
		local value = get(item.value, item)
		local right = rx + rw - pad
		if item.kind == "toggle" then
			local size = math.floor(self.rowH * 0.45)
			drawCheck(right - size, y + (self.rowH - size) / 2, size, get(item.checked, item), disabled)
			valueW = size + theme.gap
			right = right - valueW
		end
		if value and value ~= "" then
			local text = tostring(value)
			if item.kind == "choice" and focused and not disabled then
				text = "‹ " .. text .. " ›"
			end
			local vf = theme.fonts.small
			local maxV = math.floor(rw * 0.5)
			local shown = draw.fit(vf, text, maxV)
			local vw = vf:getWidth(shown)
			draw.text(vf, shown, right - vw, y + (self.rowH - vf:getHeight()) / 2, nil,
				disabled and c.disabled or (focused and c.accent or c.subtext))
			valueW = valueW + vw + theme.gap
		end
		local labelX = rx + pad
		local labelW = rw - pad * 2 - valueW
		local detail = get(item.detail, item)
		if self.twoLine and detail then
			local lh, dh = font:getHeight(), theme.fonts.small:getHeight()
			local top = y + (self.rowH - lh - dh) / 2
			draw.text(font, get(item.label, item), labelX, top, labelW, labelColor)
			draw.text(theme.fonts.small, detail, labelX, top + lh, labelW, disabled and c.disabled or c.subtext)
		else
			draw.text(font, get(item.label, item), labelX, y + (self.rowH - font:getHeight()) / 2, labelW, labelColor)
		end
	end
	love.graphics.setScissor()
	if #self.items > rows then
		local trackH = self.h - theme.gap * 2
		local barH = math.max(theme.px(16), trackH * rows / #self.items)
		local barY = self.y + theme.gap + (trackH - barH) * (self.top - 1) / math.max(1, #self.items - rows)
		theme.setColor(c.outline)
		love.graphics.rectangle("fill", self.x + self.w - theme.px(4), barY, theme.px(3), barH, 2, 2)
	end
	love.graphics.pop()
end

return List
