--- Logical-to-physical display mapping (from Aesthetic Spruce's src/display.lua)
---
--- spruce devices with a portrait panel used in landscape (Miniloong Pocket 1, RG28XX) expose a
--- rotated framebuffer to SDL: on the Miniloong LÖVE sees 720x960 while the UI is 960x720. PyUI
--- renders a logical canvas and rotates it by the device's rotation; this does the same.
local display = {}

local canvas = nil
local rotation = 0
local logicalW, logicalH = 640, 480

function display.load(w, h)
	logicalW, logicalH = w, h
	rotation = (tonumber(os.getenv("ROTATION") or "0") or 0) % 360
	if rotation ~= 0 then
		canvas = love.graphics.newCanvas(w, h)
	end
end

function display.beginFrame()
	if canvas then
		love.graphics.setCanvas({ canvas, stencil = true })
		love.graphics.clear(0, 0, 0, 1)
	end
end

function display.endFrame()
	if not canvas then
		return
	end
	love.graphics.setCanvas()
	local pw, ph = love.graphics.getDimensions()
	love.graphics.push("all")
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.setBlendMode("alpha", "premultiplied")
	-- rotate about the centre, clockwise like PyUI's SDL_RenderCopyEx
	love.graphics.draw(canvas, pw / 2, ph / 2, math.rad(rotation), 1, 1, logicalW / 2, logicalH / 2)
	love.graphics.pop()
end

return display
