--- Main menu: start a scrape and every setting it uses
local app = require("app")
local settings = require("settings")
local regions = require("scraper.regions")
local theme = require("ui.theme")
local draw = require("ui.draw")
local List = require("ui.list")
local modal = require("ui.modal")
local version = require("version")

local home = {}
local list

local THREAD_CHOICES = { 0, 1, 2, 3, 4 }

local function cycle(values, current, dir)
	local idx = 1
	for i, v in ipairs(values) do
		if v == current then
			idx = i
		end
	end
	return values[(idx - 1 + dir) % #values + 1]
end

local function plural(n, one, many)
	return string.format("%d %s", n, n == 1 and one or (many or one .. "s"))
end

local function scrapeDetail()
	if app.scanning then
		return "Scanning your games" .. (app.scanLabel and (": " .. app.scanLabel) or "…")
	end
	if not app.library then
		return ""
	end
	local names, games = app.selectedSystems()
	if #names == 0 then
		if settings.get("overwrite") then
			return "No systems selected"
		end
		return "Every selected game already has box art"
	end
	local what = settings.get("overwrite") and "" or " without box art"
	return plural(games, "game") .. what .. " in " .. plural(#names, "system")
end

local function selectedCount()
	local on, total = 0, 0
	for _, sys in ipairs(app.library or {}) do
		if sys.platform then
			total = total + 1
			if settings.isSelected(sys.name) then
				on = on + 1
			end
		end
	end
	return on, total
end

local function accountDetail()
	local acc = app.account
	if settings.get("username") == "" then
		return "Not set: anonymous scraping is slow and often refused"
	end
	if app.checkingAccount then
		return "Checking…"
	end
	if acc and acc.loginError then
		return "ScreenScraper rejected this login"
	end
	if acc and acc.allowed then
		return "Your account allows " .. plural(acc.allowed, "thread")
	end
	return "Press A to check it or change it"
end

local function threadValue()
	local n = settings.get("threads")
	if n == 0 then
		return "Account maximum"
	end
	return tostring(n)
end

local function threadDetail()
	local acc = app.account
	if settings.get("username") == "" then
		return "Anonymous scraping always uses 1 thread"
	end
	if acc and acc.allowed then
		return "Your account allows " .. plural(acc.allowed, "thread") .. "; more than that are not used"
	end
	return "Contributors and donors get more threads at screenscraper.fr"
end

local function startScrape()
	local names, games = app.selectedSystems()
	if #names == 0 then
		modal.open({
			title = "Nothing to scrape",
			message = app.library and #app.library == 0
					and "No games were found in Roms/. Copy some games to the card first."
				or "Every selected system already has box art. Turn on \"Replace existing box art\" to download it again, or select more systems.",
		})
		return
	end
	if app.skyscraper and app.skyscraper.missing then
		modal.open({
			title = "Skyscraper is missing",
			message = "This copy of Spruce Scraper has no Skyscraper program. Reinstall it from the Game Nursery.",
		})
		return
	end
	if settings.get("overwrite") then
		modal.open({
			title = "Replace box art?",
			message = string.format(
				"Box art for up to %d games will be downloaded again and replace what is there. "
					.. "The old images are moved to %s.",
				games, app.dataPath("replaced")),
			buttons = {
				{ label = "Replace", onPress = app.startScrape },
				{ label = "Cancel" },
			},
		})
		return
	end
	app.startScrape()
end

local function build()
	return {
		{
			label = "Scrape box art",
			detail = scrapeDetail,
			kind = "action",
			disabled = function()
				return app.scanning or not app.library
			end,
			onPress = startScrape,
		},
		{
			label = "Systems",
			value = function()
				local on, total = selectedCount()
				return app.library and string.format("%d of %d", on, total) or ""
			end,
			detail = "Choose which systems to scrape",
			kind = "action",
			disabled = function()
				return not app.library
			end,
			onPress = function()
				app.switch("systems")
			end,
		},
		{
			label = "ScreenScraper account",
			value = function()
				local user = settings.get("username")
				return user ~= "" and user or "Not set"
			end,
			detail = accountDetail,
			kind = "action",
			onPress = function()
				app.switch("account")
			end,
		},
		{
			label = "Box art region",
			value = function()
				return regions.describe(settings.get("region"), app.paths.spruceRegion)
			end,
			detail = function()
				if settings.get("region") == "Auto" then
					return "Uses the region in each file name, e.g. (Europe)"
				end
				return "Always prefers this region's box"
			end,
			kind = "choice",
			onChange = function(_, dir)
				settings.set("region", cycle(regions.CHOICES, settings.get("region"), dir))
			end,
		},
		{
			label = "Threads",
			value = threadValue,
			detail = threadDetail,
			kind = "choice",
			onChange = function(_, dir)
				settings.set("threads", cycle(THREAD_CHOICES, settings.get("threads"), dir))
			end,
		},
		{
			label = "Replace existing box art",
			detail = function()
				return settings.get("overwrite") and "Downloads art for every game again" or "Only games without box art"
			end,
			kind = "toggle",
			checked = function()
				return settings.get("overwrite")
			end,
			onChange = function()
				settings.set("overwrite", not settings.get("overwrite"))
			end,
		},
		{
			label = "Rescan games",
			detail = "After adding games or box art from a PC",
			kind = "action",
			disabled = function()
				return app.scanning
			end,
			onPress = app.rescan,
		},
		{
			label = "About",
			detail = "Credits, ScreenScraper, licences",
			kind = "action",
			onPress = function()
				app.switch("about")
			end,
		},
		{
			label = "Exit",
			kind = "action",
			onPress = function()
				love.event.quit()
			end,
		},
	}
end

function home.enter()
	if not list then
		list = List.new({ items = build(), twoLine = true })
	end
end

function home.update()
	if app.notice and not modal.isOpen() then
		local notice = app.notice
		app.notice = nil
		modal.open({ title = "Spruce Scraper", message = notice })
	end
end

function home.handle(action)
	if action == "b" then
		love.event.quit()
		return
	end
	list:handle(action)
end

function home.draw()
	draw.background()
	draw.header("Spruce Scraper", version.string())
	list:draw()
	draw.footer({ { "A", "Select" }, { "←→", "Change" }, { "B", "Exit" } })
	if app.skyscraper and app.skyscraper.failed and not app.skyscraper.missing then
		local f = theme.fonts.tiny
		draw.text(f, "Skyscraper did not start on this device: see " .. app.dataPath("logs"), theme.pad,
			theme.h - theme.footerH - f:getHeight() - theme.px(2), theme.w - theme.pad * 2, theme.colors.bad)
	end
end

return home
