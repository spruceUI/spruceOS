--- Credits and where the data comes from
local app = require("app")
local theme = require("ui.theme")
local draw = require("ui.draw")
local version = require("version")

local screen = {}
local scroll = 0
local contentH = 0

local TEXT = {
	{ "Spruce Scraper " .. version.string(), "bodyBold" },
	{ "Downloads box art for your games from ScreenScraper and saves it where spruce looks for it. "
		.. "Not affiliated with ScreenScraper, Skyscraper or Scrappy.", "small" },
	{ "Box art and game data", "bodyBold" },
	{ "ScreenScraper (screenscraper.fr) is run by volunteers. Contributing or donating there is what "
		.. "gets an account more threads.", "small" },
	{ "Skyscraper", "bodyBold" },
	{ "The scraping engine underneath: Skyscraper by Lars Muldjord, maintained by Gemba "
		.. "(github.com/Gemba/skyscraper), GPL-3.0. Its licence and source details are in "
		.. "App/SpruceScraper/.scraper/skyscraper.", "small" },
	{ "Scrappy", "bodyBold" },
	{ "This app follows Scrappy, the art scraper for muOS by Gabriel Vale (github.com/gabrielfvale/scrappy, "
		.. "MIT): Skyscraper as the backend, driven from a LÖVE app with a live progress view.", "small" },
	{ "Aesthetic", "bodyBold" },
	{ "The spruce runtime (LÖVE on spruce, display rotation, button layout per device) and the on-screen "
		.. "keyboard layout come from Aesthetic by Jonathan Avila (MIT), through Aesthetic Spruce.", "small" },
	{ "Also", "bodyBold" },
	{ "LÖVE 11.5 (zlib licence), Inter font (SIL OFL 1.1), json.lua by rxi (MIT).", "small" },
}

function screen.enter()
	scroll = 0
end

function screen.handle(action)
	local step = theme.px(40)
	local visible = theme.h - theme.headerH - theme.footerH - theme.pad * 2
	if action == "down" then
		scroll = math.min(math.max(0, contentH - visible), scroll + step)
	elseif action == "up" then
		scroll = math.max(0, scroll - step)
	elseif action == "a" or action == "b" then
		app.switch("home")
	end
end

function screen.draw()
	draw.background()
	draw.header("About", app.skyscraper and app.skyscraper.version and ("Skyscraper " .. app.skyscraper.version) or nil)
	local x, w = theme.pad, theme.w - theme.pad * 2
	local top = theme.headerH + theme.pad
	love.graphics.push("all")
	love.graphics.setScissor(0, theme.headerH, theme.w, theme.h - theme.headerH - theme.footerH)
	local y = top - scroll
	for _, block in ipairs(TEXT) do
		local font = theme.fonts[block[2]]
		local color = block[2] == "bodyBold" and theme.colors.text or theme.colors.textDim
		y = y + draw.paragraph(font, block[1], x, y, w, color) + (block[2] == "small" and theme.pad or theme.px(2))
	end
	contentH = y + scroll - top
	love.graphics.pop()
	draw.footer({ { "↑↓", "Scroll" }, { "B", "Back" } })
end

return screen
