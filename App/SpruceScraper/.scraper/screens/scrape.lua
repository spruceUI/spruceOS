--- Scraping progress: per-system and overall bars, the game being looked up, counts, threads,
--- time left, the last cover saved and the last lines of Skyscraper's log
local app = require("app")
local job = require("scraper.job")
local util = require("scraper.util")
local theme = require("ui.theme")
local draw = require("ui.draw")
local modal = require("ui.modal")

local screen = {}
local s

local PHASES = {
	gather = "Looking up games on ScreenScraper",
	render = "Making box art images",
	install = "Saving box art",
}

local LOG_LINES = 4

local function reset()
	s = {
		systemIndex = 0,
		systemCount = 0,
		label = "Starting…",
		phase = nil,
		sysTodo = 0,
		sysDone = 0,
		totalTodo = 0,
		totalDone = 0,
		folderBase = 0,
		found = 0,
		notFound = 0,
		saved = 0,
		threads = nil,
		allowed = nil,
		anonymous = false,
		title = nil,
		status = nil,
		eta = nil,
		elapsed = 0,
		log = {},
		stopping = false,
		cover = nil,
		coverTitle = nil,
		pendingCover = nil,
		coverTimer = 0,
	}
end

local function addLog(text, color)
	s.log[#s.log + 1] = { text = text, color = color }
	while #s.log > LOG_LINES do
		table.remove(s.log, 1)
	end
end

local function loadCover(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local data = f:read("*a")
	f:close()
	local ok, image = pcall(function()
		return love.graphics.newImage(love.filesystem.newFileData(data, "cover.png"))
	end)
	return ok and image or nil
end

function screen.enter()
	reset()
end

function screen.onEvent(ev)
	local c = theme.colors
	local k = ev.kind
	if k == "job_start" then
		s.totalTodo = ev.todo or 0
	elseif k == "system_start" then
		s.systemIndex, s.systemCount = ev.index, ev.count
		s.label = ev.label
		s.sysTodo, s.sysDone = ev.todo or 0, 0
		s.sysBase = s.totalDone
		s.eta = nil
	elseif k == "phase" then
		s.phase = ev.phase
		if ev.phase == "gather" then
			s.folderBase = s.totalDone
			s.folderSysBase = s.sysDone
			s.runDone = 0
		end
	elseif k == "game" then
		-- counted, not read from the line: threads finish out of order, so its number jumps back
		s.runDone = (s.runDone or 0) + 1
		s.totalDone = math.min(s.totalTodo, s.folderBase + s.runDone)
		s.sysDone = math.min(s.sysTodo, (s.folderSysBase or 0) + s.runDone)
		s.title, s.status = ev.title, ev.status
		if ev.status == "found" then
			s.found = s.found + 1
		elseif ev.status == "missing" then
			s.notFound = s.notFound + 1
			addLog("Not found: " .. tostring(ev.title), c.warn)
		end
	elseif k == "threads" then
		s.threads = ev.threads or s.threads
		s.allowed = ev.allowed or s.allowed
		s.anonymous = ev.anonymous or false
	elseif k == "start" then
		s.threads = ev.threads or s.threads
	elseif k == "eta" then
		s.eta = ev.seconds
	elseif k == "saved" then
		s.saved = s.saved + 1
		s.pendingCover = ev.path
		s.pendingTitle = ev.title
	elseif k == "login_error" then
		addLog("ScreenScraper rejected the login", c.bad)
	elseif k == "busy" then
		addLog("ScreenScraper is busy: " .. tostring(ev.text), c.warn)
	elseif k == "stop" then
		addLog(tostring(ev.text), c.bad)
	elseif k == "error" then
		addLog(tostring(ev.text), c.bad)
	elseif k == "problem" then
		-- a system's run ended badly; when Skyscraper said why, that line is already in the log
		if ev.unseen then
			addLog(tostring(ev.label) .. ": " .. tostring(ev.text), c.bad)
		end
	elseif k == "account" then
		addLog("Logging in as " .. tostring(ev.user), c.subtext)
	elseif k == "job_done" then
		if s.cover then
			s.cover:release()
			s.cover = nil
		end
		app.switch("summary", { result = ev, elapsed = s.elapsed })
	end
end

function screen.update(dt)
	s.elapsed = s.elapsed + dt
	s.coverTimer = s.coverTimer - dt
	-- decoding a cover costs a few frames on a handheld: at most two a second
	if s.pendingCover and s.coverTimer <= 0 then
		local image = loadCover(s.pendingCover)
		if image then
			if s.cover then
				s.cover:release()
			end
			s.cover, s.coverTitle = image, s.pendingTitle
		end
		s.pendingCover = nil
		s.coverTimer = 0.5
	end
end

local function confirmStop()
	modal.open({
		title = "Stop scraping?",
		message = "Box art downloaded so far is saved first: the games in progress finish, then their images are made. "
			.. "For a large system that can take a minute.",
		buttons = {
			{
				label = "Stop",
				onPress = function()
					s.stopping = true
					job.cancel()
				end,
			},
			{ label = "Keep going" },
		},
		focus = 2,
	})
end

function screen.handle(action)
	if action == "b" then
		if s.stopping then
			-- a second request ends the image-making run too: it saves the images made so far
			job.cancel(true)
		else
			confirmStop()
		end
	end
end

local function timeLeft()
	if s.eta and s.eta > 0 then
		return s.eta
	end
	if s.totalDone > 0 and s.totalTodo > s.totalDone then
		return s.elapsed / s.totalDone * (s.totalTodo - s.totalDone)
	end
	return nil
end

local function drawCover(x, y, w, h)
	local c = theme.colors
	theme.setColor(c.surface)
	love.graphics.rectangle("fill", x, y, w, h, theme.radius, theme.radius)
	local captionH = theme.fonts.tiny:getHeight() + theme.gap
	if s.cover then
		local iw, ih = s.cover:getDimensions()
		local boxW, boxH = w - theme.gap * 2, h - theme.gap * 2 - captionH
		local scale = math.min(boxW / iw, boxH / ih)
		love.graphics.setColor(1, 1, 1, 1)
		love.graphics.draw(s.cover, math.floor(x + (w - iw * scale) / 2), math.floor(y + theme.gap + (boxH - ih * scale) / 2),
			0, scale, scale)
		draw.text(theme.fonts.tiny, s.coverTitle or "", x + theme.gap, y + h - captionH, w - theme.gap * 2, c.subtext, "center")
	else
		draw.text(theme.fonts.small, "Box art appears here", x, y + h / 2 - theme.fonts.small:getHeight() / 2, w,
			c.disabled, "center")
	end
end

function screen.draw()
	local c = theme.colors
	draw.background()
	local note = s.systemCount > 0 and string.format("System %d of %d", s.systemIndex, s.systemCount) or ""
	draw.header(s.stopping and "Stopping…" or "Scraping box art", note)

	local pad = theme.pad
	local portrait = theme.h > theme.w
	local top = theme.headerH + pad
	local bottomLimit = theme.h - theme.footerH - pad - LOG_LINES * theme.fonts.tiny:getHeight()
	local coverW = portrait and 0 or math.floor(math.min(theme.w * 0.3, bottomLimit - top))
	local x = pad
	local w = theme.w - pad * 2 - (coverW > 0 and (coverW + pad) or 0)
	local y = top

	draw.text(theme.fonts.title, s.label, x, y, w, c.text)
	y = y + theme.fonts.title:getHeight()
	draw.text(theme.fonts.small, PHASES[s.phase] or "Preparing…", x, y, w, c.subtext)
	y = y + theme.fonts.small:getHeight() + theme.gap

	local barH = theme.px(14)
	draw.progress(x, y, w, barH, s.sysTodo > 0 and s.sysDone / s.sysTodo or 0)
	y = y + barH + theme.px(4)
	draw.text(theme.fonts.small, string.format("%d of %d games", s.sysDone, s.sysTodo), x, y, w, c.textDim)
	y = y + theme.fonts.small:getHeight() + theme.gap

	if s.systemCount > 1 then
		local thin = theme.px(7)
		draw.progress(x, y, w, thin, s.totalTodo > 0 and s.totalDone / s.totalTodo or 0, c.textDim)
		y = y + thin + theme.px(4)
		draw.text(theme.fonts.tiny, string.format("All systems: %d of %d games", s.totalDone, s.totalTodo), x, y, w,
			c.subtext)
		y = y + theme.fonts.tiny:getHeight() + theme.gap
	end

	if s.title then
		local dot = theme.px(10)
		local color = s.status == "found" and c.good or (s.status == "missing" and c.bad or c.subtext)
		local f = theme.fonts.body
		theme.setColor(color)
		love.graphics.circle("fill", x + dot / 2, y + f:getHeight() / 2, dot / 2)
		draw.text(f, s.title, x + dot + theme.gap, y, w - dot - theme.gap, c.text)
		y = y + f:getHeight() + theme.gap
	end

	local f = theme.fonts.small
	local threads
	if s.anonymous then
		threads = "1 (no account)"
	elseif s.threads and s.allowed and s.allowed ~= s.threads then
		threads = string.format("%d of %d allowed", s.threads, s.allowed)
	elseif s.threads then
		threads = tostring(s.threads)
	else
		threads = "…"
	end
	local left = timeLeft()
	local rows = {
		{ "Saved", tostring(s.saved), c.good },
		{ "Not found", tostring(s.notFound), s.notFound > 0 and c.warn or c.textDim },
		{ "Threads", threads, c.textDim },
		{ "Time", util.formatSeconds(s.elapsed) .. (left and ("  ·  about " .. util.formatSeconds(left) .. " left") or ""),
			c.textDim },
	}
	local labelW = 0
	for _, r in ipairs(rows) do
		labelW = math.max(labelW, f:getWidth(r[1]))
	end
	for _, r in ipairs(rows) do
		draw.text(f, r[1], x, y, labelW, c.subtext)
		draw.text(f, r[2], x + labelW + theme.pad, y, w - labelW - theme.pad, r[3])
		y = y + f:getHeight() + theme.px(2)
	end

	if portrait then
		local h = bottomLimit - y - theme.gap
		if h > theme.px(80) then
			drawCover(x, y + theme.gap, w, h)
		end
	elseif coverW > 0 then
		drawCover(theme.w - pad - coverW, top, coverW, bottomLimit - top)
	end

	local tf = theme.fonts.tiny
	local ly = theme.h - theme.footerH - theme.gap - LOG_LINES * tf:getHeight()
	for i, line in ipairs(s.log) do
		draw.text(tf, line.text, pad, ly + (i - 1) * tf:getHeight(), theme.w - pad * 2, line.color)
	end
	draw.footer(s.stopping and { { "B", "Stop sooner" } } or { { "B", "Stop" } })
end

return screen
