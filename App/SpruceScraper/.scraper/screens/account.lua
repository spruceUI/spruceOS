--- ScreenScraper account: user name, password, and a check of what the account allows
local app = require("app")
local settings = require("settings")
local skyconfig = require("scraper.skyconfig")
local theme = require("ui.theme")
local draw = require("ui.draw")
local List = require("ui.list")
local modal = require("ui.modal")

local screen = {}
local list

local function oldSkyscraper()
	local v = app.skyscraper and app.skyscraper.version
	if not v then
		return false
	end
	local major, minor = v:match("^(%d+)%.(%d+)")
	major, minor = tonumber(major), tonumber(minor)
	return major and (major < 3 or (major == 3 and minor < 21))
end

local function editField(key, title, secret)
	app.switch("keyboard", {
		title = title,
		value = settings.get(key),
		secret = secret,
		onDone = function(value)
			settings.set(key, value)
			app.account = nil
			app.switch("account")
		end,
		onCancel = function()
			app.switch("account")
		end,
	})
end

local function checkDetail()
	if app.checkingAccount then
		return "Asking ScreenScraper…"
	end
	local acc = app.account
	if not acc then
		return "Logs in and reads how many threads the account may use"
	end
	if acc.loginError then
		return "Login failed: check the user name and password"
	end
	if acc.allowed then
		return string.format("Logged in: %d thread%s allowed", acc.allowed, acc.allowed == 1 and "" or "s")
	end
	if acc.anonymous then
		return "No account: anonymous, 1 thread"
	end
	return acc.message or "No answer from ScreenScraper; try again later"
end

local function build()
	local items = {
		{
			label = "User name",
			value = function()
				local u = settings.get("username")
				return u ~= "" and u or "Not set"
			end,
			kind = "action",
			onPress = function()
				editField("username", "ScreenScraper user name", false)
			end,
		},
		{
			label = "Password",
			value = function()
				local p = settings.get("password")
				return p ~= "" and string.rep("•", math.min(#p, 12)) or "Not set"
			end,
			kind = "action",
			onPress = function()
				editField("password", "ScreenScraper password", true)
			end,
		},
		{
			label = "Check account",
			detail = checkDetail,
			kind = "action",
			disabled = function()
				return app.checkingAccount or app.scraping or settings.get("username") == ""
			end,
			onPress = app.checkAccount,
		},
		{
			label = "Remove account",
			kind = "action",
			disabled = function()
				return settings.get("username") == "" and settings.get("password") == ""
			end,
			onPress = function()
				modal.open({
					title = "Remove account?",
					message = "Spruce Scraper forgets the user name and password. Scraping then runs anonymously with one thread.",
					buttons = {
						{
							label = "Remove",
							onPress = function()
								settings.set("username", "")
								settings.set("password", "")
								app.account = nil
							end,
						},
						{ label = "Cancel" },
					},
				})
			end,
		},
	}
	return items
end

function screen.enter()
	-- kept across visits, so coming back from the keyboard keeps the row that was edited
	if not list then
		list = List.new({ items = build(), twoLine = true, h = theme.px(58) * 4 })
	end
end

function screen.handle(action)
	if action == "b" then
		app.switch("home")
	else
		list:handle(action)
	end
end

function screen.draw()
	draw.background()
	draw.header("ScreenScraper account", nil)
	list:draw()
	local c = theme.colors
	local x, w = theme.pad, theme.w - theme.pad * 2
	local y = list.y + list.h + theme.gap
	local f = theme.fonts.small
	if oldSkyscraper() and skyconfig.passwordNeedsNewSkyscraper(settings.get("password")) then
		y = y + draw.paragraph(f, "This build's Skyscraper (" .. app.skyscraper.version .. ") cannot log in with a password "
			.. "that has symbols or spaces in it. Use letters, digits and - . _ ~ only, or update Spruce Scraper.",
			x, y, w, c.warn) + theme.gap
	end
	draw.paragraph(f, "Free accounts scrape with one thread. ScreenScraper gives contributors and donors more "
		.. "threads, and Spruce Scraper uses as many as the account allows. Create an account at "
		.. "screenscraper.fr. You can also put username=... and password=... lines in "
		.. "App/SpruceScraper/screenscraper.txt on a PC; it is read once at the next start.",
		x, y, w, c.subtext)
	draw.footer({ { "A", "Select" }, { "B", "Back" } })
end

return screen
