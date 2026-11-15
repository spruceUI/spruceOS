--- On-screen keyboard: three layers (lower, upper, symbols) plus a control row
---
--- A types the key under the cursor, B deletes a character, Y switches layer, X types a space,
--- Start finishes. Moving off the top or bottom row wraps. The layout follows the virtual
--- keyboard of Aesthetic (and of the original muOS app); ScreenScraper user names and
--- passwords may hold any printable ASCII, so the symbol layer carries all of it.
local theme = require("ui.theme")
local draw = require("ui.draw")

local Keyboard = {}
Keyboard.__index = Keyboard

local LAYERS = {
	{ "1234567890", "qwertyuiop", "asdfghjkl-", "zxcvbnm._@" },
	{ "1234567890", "QWERTYUIOP", "ASDFGHJKL-", "ZXCVBNM._@" },
	-- all 32 ASCII punctuation characters
	{ "1234567890", "!\"#$%&'()*+", ",-./:;<=>?@", "[\\]^_`{|}~" },
}

local CONTROLS = { "ABC", "space", "del", "OK" }

function Keyboard.new(opts)
	local self = setmetatable({}, Keyboard)
	self.title = opts.title or "Enter text"
	self.value = opts.value or ""
	self.secret = opts.secret or false
	self.reveal = not self.secret
	self.maxLength = opts.maxLength or 64
	self.onDone = opts.onDone
	self.onCancel = opts.onCancel
	self.layer = 1
	self.row, self.col = 2, 1
	return self
end

function Keyboard:rows()
	local rows = {}
	for i, s in ipairs(LAYERS[self.layer]) do
		local keys = {}
		for ch in s:gmatch(".") do
			keys[#keys + 1] = ch
		end
		rows[i] = keys
	end
	rows[#rows + 1] = CONTROLS
	return rows
end

function Keyboard:type(ch)
	if #self.value < self.maxLength then
		self.value = self.value .. ch
	end
end

function Keyboard:press()
	local rows = self:rows()
	local key = rows[self.row][self.col]
	if self.row == #rows then
		if key == "ABC" then
			self.layer = self.layer % #LAYERS + 1
		elseif key == "space" then
			self:type(" ")
		elseif key == "del" then
			self.value = self.value:sub(1, -2)
		elseif key == "OK" and self.onDone then
			self.onDone(self.value)
		end
	else
		self:type(key)
	end
end

function Keyboard:handle(action)
	local rows = self:rows()
	if action == "up" or action == "down" then
		local oldLen = #rows[self.row]
		self.row = (self.row - 1 + (action == "down" and 1 or -1)) % #rows + 1
		-- keep the horizontal position proportional between rows of different lengths
		local newLen = #rows[self.row]
		self.col = math.max(1, math.min(newLen, math.floor((self.col - 0.5) * newLen / oldLen) + 1))
	elseif action == "left" then
		self.col = (self.col - 2) % #rows[self.row] + 1
	elseif action == "right" then
		self.col = self.col % #rows[self.row] + 1
	elseif action == "a" then
		self:press()
	elseif action == "b" then
		if self.value == "" then
			if self.onCancel then
				self.onCancel()
			end
		else
			self.value = self.value:sub(1, -2)
		end
	elseif action == "y" then
		self.layer = self.layer % #LAYERS + 1
		rows = self:rows()
		self.col = math.min(self.col, #rows[self.row])
	elseif action == "x" then
		self:type(" ")
	elseif action == "select" then
		self.reveal = not self.reveal
	elseif action == "start" then
		if self.onDone then
			self.onDone(self.value)
		end
	else
		return false
	end
	return true
end

function Keyboard:draw()
	local c = theme.colors
	draw.background()
	draw.header(self.title, nil)
	local pad = theme.pad
	local fieldY = theme.headerH + theme.pad
	local fieldH = theme.px(44)
	theme.setColor(c.surface)
	love.graphics.rectangle("fill", pad, fieldY, theme.w - pad * 2, fieldH, theme.radius, theme.radius)
	local f = theme.fonts.body
	local maxW = theme.w - pad * 4
	-- keep the end of long values visible
	local visible = self.value
	local shown
	while true do
		shown = self.reveal and visible or string.rep("•", #visible)
		if visible == "" or f:getWidth(draw.clean(shown) .. "|") <= maxW then
			break
		end
		visible = visible:sub(2)
	end
	draw.text(f, shown .. ((love.timer.getTime() % 1) < 0.5 and "|" or " "), pad * 2,
		fieldY + (fieldH - f:getHeight()) / 2, nil, c.text)

	local rows = self:rows()
	local top = fieldY + fieldH + theme.pad
	local bottom = theme.h - theme.footerH - theme.gap
	local keyGap = theme.px(5)
	local keyH = math.floor((bottom - top - keyGap * (#rows - 1)) / #rows)
	local areaW = theme.w - pad * 2
	for r, keys in ipairs(rows) do
		local kw = math.floor((areaW - keyGap * (#keys - 1)) / #keys)
		local y = top + (r - 1) * (keyH + keyGap)
		for k, key in ipairs(keys) do
			local x = pad + (k - 1) * (kw + keyGap)
			local focused = r == self.row and k == self.col
			theme.setColor(focused and c.accent or (r == #rows and c.surfaceFocus or c.surface))
			love.graphics.rectangle("fill", x, y, kw, keyH, theme.px(6), theme.px(6))
			local label = key
			if key == "ABC" then
				label = ({ "ABC", "#+=", "abc" })[self.layer]
			end
			local kf = theme.fonts.body
			draw.text(kf, label, x, y + (keyH - kf:getHeight()) / 2, kw, focused and c.onAccent or c.text, "center")
		end
	end
	local hints = { { "A", "Type" }, { "B", "Delete" }, { "Y", "Layer" }, { "START", "Done" } }
	if self.secret then
		hints[#hints + 1] = { "SELECT", self.reveal and "Hide" or "Show" }
	end
	draw.footer(hints)
end

return Keyboard
