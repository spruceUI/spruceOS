--- Spruce Scraper: box art from ScreenScraper for spruceOS, through Skyscraper
local app = require("app")
local display = require("display")
local theme = require("ui.theme")

-- LÖVE's default error screen has no gamepad exit and would strand a handheld until it is
-- power-cycled (Aesthetic Spruce's handler): log the trace to the session log and
-- last_crash.txt in the data folder, show it for a few seconds, then exit so PyUI comes back.
local function crash(msg)
	msg = tostring(msg)
	local trace = debug.traceback(msg, 3)
	print("CRASH " .. trace)
	io.stdout:flush()
	local userdata = os.getenv("SCRAPER_USERDATA")
	if userdata then
		local f = io.open(userdata .. "/last_crash.txt", "w")
		if f then
			f:write(os.date("%Y-%m-%d %H:%M:%S") .. "\n" .. trace .. "\n")
			f:close()
		end
	end
	if os.getenv("SCRAPER_AUTORUN") == "1" or os.getenv("SCRAPER_SCREENSHOT") then
		os.exit(1)
	end
	pcall(function()
		pcall(function()
			require("scraper.job").shutdown()
		end)
		love.graphics.reset()
		love.graphics.setCanvas()
		love.graphics.setFont(love.graphics.newFont(16))
		local t0 = love.timer.getTime()
		while love.timer.getTime() - t0 < 8 do
			love.event.pump()
			for name in love.event.poll() do
				if name == "quit" or name == "keypressed" or name == "gamepadpressed" or name == "joystickpressed" then
					return
				end
			end
			love.graphics.clear(0.35, 0.06, 0.06)
			love.graphics.setColor(1, 1, 1)
			love.graphics.printf("Spruce Scraper hit an error and will return to the menu.\n\n" .. msg
				.. "\n\nFull trace: " .. ((userdata or "the data folder"):gsub("^/mnt/SDCARD/", "")) .. "/last_crash.txt",
				20, 20, love.graphics.getWidth() - 40)
			love.graphics.present()
			love.timer.sleep(0.05)
		end
	end)
	os.exit(1)
end

function love.errorhandler(msg)
	crash(msg)
end

function love.threaderror(_, err)
	crash("worker thread: " .. tostring(err))
end

function love.load()
	local w = tonumber(os.getenv("WIDTH") or "") or love.graphics.getWidth()
	local h = tonumber(os.getenv("HEIGHT") or "") or love.graphics.getHeight()
	love.mouse.setVisible(false)
	love.keyboard.setKeyRepeat(false)
	theme.init(w, h)
	display.load(w, h)
	app.load()
end

function love.update(dt)
	app.update(dt)
end

function love.draw()
	display.beginFrame()
	app.draw()
	display.endFrame()
end

function love.quit()
	app.quit()
end
