--- Drawing helpers shared by the screens: header, footer hints, progress bars, fitted text
local theme = require("ui.theme")
local utf8 = require("utf8")

local draw = {}

--- Replace invalid UTF-8 with "?": LÖVE's font calls raise on it, and file names on a card are
--- whatever bytes the PC wrote
function draw.clean(text)
	text = tostring(text or "")
	for _ = 1, #text do
		local ok, pos = utf8.len(text)
		if ok then
			break
		end
		text = text:sub(1, pos - 1) .. "?" .. text:sub(pos + 1)
	end
	return text
end

--- text shortened with an ellipsis to fit maxW
function draw.fit(font, text, maxW)
	text = draw.clean(text)
	if font:getWidth(text) <= maxW then
		return text
	end
	local ell = "…"
	local lo, hi = 0, #text
	while lo < hi do
		local mid = math.floor((lo + hi + 1) / 2)
		-- cut at a UTF-8 boundary
		local cut = mid
		while cut > 0 and text:byte(cut + 1) and text:byte(cut + 1) >= 0x80 and text:byte(cut + 1) < 0xC0 do
			cut = cut - 1
		end
		if font:getWidth(text:sub(1, cut) .. ell) <= maxW then
			lo = mid
		else
			hi = mid - 1
		end
	end
	local cut = lo
	while cut > 0 and text:byte(cut + 1) and text:byte(cut + 1) >= 0x80 and text:byte(cut + 1) < 0xC0 do
		cut = cut - 1
	end
	return text:sub(1, cut) .. ell
end

function draw.text(font, text, x, y, maxW, color, align)
	theme.setColor(color or theme.colors.text)
	love.graphics.setFont(font)
	local t = maxW and draw.fit(font, text, maxW) or draw.clean(text)
	if align == "right" and maxW then
		love.graphics.print(t, math.floor(x + maxW - font:getWidth(t)), math.floor(y))
	elseif align == "center" and maxW then
		love.graphics.print(t, math.floor(x + (maxW - font:getWidth(t)) / 2), math.floor(y))
	else
		love.graphics.print(t, math.floor(x), math.floor(y))
	end
end

function draw.background()
	local c = theme.colors.background
	love.graphics.clear(c[1], c[2], c[3], 1)
end

--- Title bar: title left, optional right-hand note
function draw.header(title, note)
	local f = theme.fonts.title
	local y = math.floor((theme.headerH - f:getHeight()) / 2)
	local noteW = 0
	if note and note ~= "" then
		noteW = math.min(theme.fonts.small:getWidth(note), theme.w * 0.45)
		draw.text(theme.fonts.small, note, theme.w - theme.pad - noteW,
			math.floor((theme.headerH - theme.fonts.small:getHeight()) / 2), noteW, theme.colors.subtext, "right")
	end
	draw.text(f, title, theme.pad, y, theme.w - theme.pad * 3 - noteW, theme.colors.text)
	theme.setColor(theme.colors.outline)
	love.graphics.rectangle("fill", 0, theme.headerH - 1, theme.w, 1)
end

--- Button hints along the bottom: { { "A", "Select" }, { "B", "Back" } }
function draw.footer(hints)
	local y0 = theme.h - theme.footerH
	theme.setColor(theme.colors.surface)
	love.graphics.rectangle("fill", 0, y0, theme.w, theme.footerH)
	theme.setColor(theme.colors.outline)
	love.graphics.rectangle("fill", 0, y0, theme.w, 1)
	local f = theme.fonts.small
	local x = theme.pad
	local cy = y0 + theme.footerH / 2
	local d = math.floor(f:getHeight() * 1.15)
	for _, hint in ipairs(hints or {}) do
		local label, text = hint[1], hint[2]
		local lw = math.max(d, f:getWidth(label) + theme.px(10))
		if x + lw + theme.gap + f:getWidth(text) > theme.w - theme.pad then
			break
		end
		theme.setColor(theme.colors.textDim)
		love.graphics.rectangle("fill", x, cy - d / 2, lw, d, d / 2, d / 2)
		draw.text(f, label, x, cy - f:getHeight() / 2, lw, theme.colors.onAccent, "center")
		x = x + lw + theme.px(6)
		draw.text(f, text, x, cy - f:getHeight() / 2, nil, theme.colors.textDim)
		x = x + f:getWidth(text) + theme.pad
	end
end

function draw.progress(x, y, w, h, fraction, color)
	fraction = math.max(0, math.min(1, fraction or 0))
	local r = h / 2
	theme.setColor(theme.colors.surfaceFocus)
	love.graphics.rectangle("fill", x, y, w, h, r, r)
	if fraction > 0 then
		theme.setColor(color or theme.colors.accent)
		love.graphics.rectangle("fill", x, y, math.max(h, w * fraction), h, r, r)
	end
end

--- Wrapped paragraph; returns its height
function draw.paragraph(font, text, x, y, w, color, align)
	text = draw.clean(text)
	theme.setColor(color or theme.colors.textDim)
	love.graphics.setFont(font)
	love.graphics.printf(text, math.floor(x), math.floor(y), w, align or "left")
	local _, lines = font:getWrap(text, w)
	return #lines * font:getHeight()
end

return draw
