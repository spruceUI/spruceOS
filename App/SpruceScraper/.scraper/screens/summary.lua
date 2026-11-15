--- After a scrape: what was saved, what was not found, and why a run ended early
local app = require("app")
local util = require("scraper.util")
local theme = require("ui.theme")
local draw = require("ui.draw")
local List = require("ui.list")

local screen = {}
local result, elapsed, list, problem

local REASONS = {
	login = "ScreenScraper did not accept the user name and password. Check them under ScreenScraper account.",
	quota = "Your daily ScreenScraper limit is used up. It resets every day; run Spruce Scraper again tomorrow "
		.. "and it carries on with the games still missing art.",
	closed = "ScreenScraper is closed right now. Try again later.",
	busy = "ScreenScraper is too busy for anonymous users right now. An account gets you through.",
	blacklisted = "ScreenScraper refused this version of Skyscraper. Update Spruce Scraper.",
	failing = "Many games in a row were not found, so Skyscraper stopped.",
	space = "The SD card is almost full. Free some space and try again.",
	spawn = "Skyscraper could not be started on this device. See {logs}.",
	missing = "This copy of Spruce Scraper has no Skyscraper program. Reinstall Spruce Scraper.",
	offline = "ScreenScraper could not be reached. Connect to Wi-Fi and try again.",
	clock = "The device's clock is wrong, so secure connections fail. Set the time (or let it sync over Wi-Fi) and try again.",
	certificate = "The secure connection to ScreenScraper could not be verified. On a shared Wi-Fi, sign in to the "
		.. "network first; otherwise update spruce.",
	error = "Something went wrong. See {logs}.",
}

function screen.enter(params)
	result = params.result or {}
	elapsed = params.elapsed or 0
	local items = {}
	local problems = 0
	problem = nil
	for _, r in ipairs(result.results or {}) do
		local parts = { string.format("%d saved", r.saved or 0) }
		if (r.notFound or 0) > 0 then
			parts[#parts + 1] = string.format("%d not found", r.notFound)
		end
		-- Skyscraper ended this system's run badly: say which and why, a "0 saved" hides it
		if r.problem then
			parts[#parts + 1] = "failed"
			problems = problems + 1
			problem = problem or ((r.label or r.name) .. " could not be finished: " .. r.problem)
		end
		items[#items + 1] = { label = r.label or r.name, value = table.concat(parts, " · "), kind = "action" }
	end
	if #items == 0 then
		items[1] = { label = "No systems were scraped", kind = "info" }
	end
	if problems > 1 then
		problem = problem .. string.format(" (%d more in %s)", problems - 1, app.dataPath("logs"))
	end
	list = List.new({ items = items })
end

function screen.handle(action)
	if action == "a" or action == "b" then
		app.switch("home")
	else
		list:handle(action)
	end
end

function screen.draw()
	local c = theme.colors
	draw.background()
	local title = "Done"
	if result.stopReason then
		title = "Stopped early"
	elseif result.cancelled then
		title = "Stopped"
	end
	draw.header(title, "Took " .. util.formatSeconds(elapsed))
	local x, w = theme.pad, theme.w - theme.pad * 2
	local y = theme.headerH + theme.pad
	draw.text(theme.fonts.big, tostring(result.saved or 0), x, y, w, c.accent)
	local bigW = theme.fonts.big:getWidth(tostring(result.saved or 0))
	draw.text(theme.fonts.body, (result.saved == 1 and "box art image saved" or "box art images saved"),
		x + bigW + theme.gap, y + theme.fonts.big:getHeight() - theme.fonts.body:getHeight() - theme.px(4),
		w - bigW - theme.gap, c.text)
	y = y + theme.fonts.big:getHeight() + theme.px(4)
	local message
	if result.stopReason then
		message = REASONS[result.stopReason] or ("Stopped: " .. tostring(result.stopReason))
		message = (message:gsub("{logs}", app.dataPath("logs")))
	elseif problem then
		message = problem
	elseif (result.notFound or 0) > 0 then
		message = string.format("%d game%s not found on ScreenScraper. Renaming a file to its No-Intro or "
			.. "Redump name usually fixes that.", result.notFound, result.notFound == 1 and " was" or "s were")
	else
		message = "spruce converts the new images when you return to the menu."
	end
	y = y + draw.paragraph(theme.fonts.small, message, x, y, w, (result.stopReason or problem) and c.warn or c.subtext)
		+ theme.gap
	list.y = y
	list.h = theme.h - theme.footerH - y - theme.gap
	list:draw()
	draw.footer({ { "A", "OK" } })
end

return screen
