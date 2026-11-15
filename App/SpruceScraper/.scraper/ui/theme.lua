--- Colours, fonts and sizes, scaled to the screen
---
--- The palette is Aesthetic Spruce's dark UI palette with spruce's gold (#D6B45E, the SPRUCE
--- theme's accent) in place of its indigo. Sizes are set for 640x480 and scale with the screen;
--- portrait screens (Zero 40, 480x800) scale by width so rows keep their length.
local theme = {}

local function hex(h, a)
	return {
		tonumber(h:sub(2, 3), 16) / 255,
		tonumber(h:sub(4, 5), 16) / 255,
		tonumber(h:sub(6, 7), 16) / 255,
		a or 1,
	}
end

theme.colors = {
	background = hex("#101011"),
	surface = hex("#17181A"),
	surfaceFocus = hex("#24262C"),
	outline = hex("#2E3037"),
	text = hex("#FFFFFF"),
	textDim = hex("#E3E4E5"),
	subtext = hex("#97979A"),
	disabled = hex("#5A5B60"),
	accent = hex("#D6B45E"),
	onAccent = hex("#17181A"),
	good = hex("#5BBF7F"),
	warn = hex("#E3A94B"),
	bad = hex("#E0605A"),
	scrim = hex("#000000", 0.6),
}

local FONT_SEMIBOLD = "assets/fonts/inter/inter_24pt_semibold.ttf"
local FONT_EXTRABOLD = "assets/fonts/inter/inter_24pt_extrabold.ttf"

function theme.init(w, h)
	theme.w, theme.h = w, h
	local s = math.min(w / 640, h / 480)
	if h > w then
		s = w / 520
	end
	theme.s = s
	local function px(v)
		return math.max(1, math.floor(v * s + 0.5))
	end
	theme.px = px
	theme.fonts = {
		title = love.graphics.newFont(FONT_EXTRABOLD, px(24)),
		body = love.graphics.newFont(FONT_SEMIBOLD, px(19)),
		bodyBold = love.graphics.newFont(FONT_EXTRABOLD, px(19)),
		small = love.graphics.newFont(FONT_SEMIBOLD, px(15)),
		tiny = love.graphics.newFont(FONT_SEMIBOLD, px(13)),
		big = love.graphics.newFont(FONT_EXTRABOLD, px(36)),
	}
	theme.pad = px(16)
	theme.gap = px(8)
	theme.radius = px(8)
	theme.rowH = px(44)
	theme.headerH = px(58)
	theme.footerH = px(40)
end

function theme.setColor(c, alpha)
	love.graphics.setColor(c[1], c[2], c[3], alpha or c[4] or 1)
end

return theme
