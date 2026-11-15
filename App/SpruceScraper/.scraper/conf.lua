--- LÖVE configuration (window setup as in Aesthetic Spruce's src/conf.lua)
function love.conf(t)
	local dev = os.getenv("DEV") == "true"
	t.version = "11.5"
	t.identity = "SpruceScraper"
	t.window.title = "Spruce Scraper"
	t.window.width = tonumber(os.getenv("WIDTH") or "") or 640
	t.window.height = tonumber(os.getenv("HEIGHT") or "") or 480
	-- portrait panels used in landscape: the physical window is HEIGHTxWIDTH, display.lua rotates
	local rotation = tonumber(os.getenv("ROTATION") or "0") or 0
	if rotation % 180 ~= 0 then
		t.window.width, t.window.height = t.window.height, t.window.width
	end
	t.window.resizable = false
	t.window.msaa = 0
	t.window.fullscreen = not dev
	t.window.fullscreentype = "desktop"
	t.window.borderless = true
	t.window.vsync = 1
	t.accelerometerjoystick = false
	t.modules.audio = false
	t.modules.sound = false
	t.modules.physics = false
	t.modules.touch = false
	t.modules.video = false
	t.modules.thread = true
	t.modules.mouse = true
end
