--- Which systems to scrape
local app = require("app")
local settings = require("settings")
local draw = require("ui.draw")
local List = require("ui.list")

local screen = {}
local list

local function build()
	local items = {}
	for _, sys in ipairs(app.library or {}) do
		local supported = sys.platform ~= nil
		items[#items + 1] = {
			label = sys.label,
			detail = supported and string.format("%d game%s · %d without box art", sys.total,
				sys.total == 1 and "" or "s", sys.missing) or "Not on ScreenScraper: nothing to download",
			kind = "toggle",
			disabled = not supported,
			checked = function()
				return supported and settings.isSelected(sys.name)
			end,
			onChange = function()
				settings.setSelected(sys.name, not settings.isSelected(sys.name))
			end,
		}
	end
	if #items == 0 then
		items[1] = { label = "No games found in Roms/", kind = "info" }
	end
	return items
end

local function setAll(on)
	for _, sys in ipairs(app.library or {}) do
		if sys.platform then
			settings.values.excluded[sys.name] = (not on) or nil
		end
	end
	settings.save()
end

function screen.enter()
	local index = list and list.index or 1
	list = List.new({ items = build(), twoLine = true })
	list.index = index
	list:clamp()
end

function screen.onEvent(ev)
	if ev.kind == "scan_done" and list then
		local index = list.index
		list:setItems(build())
		list.index = index
		list:clamp()
	end
end

function screen.handle(action)
	if action == "b" then
		app.switch("home")
	elseif action == "x" then
		setAll(true)
	elseif action == "y" then
		setAll(false)
	else
		list:handle(action)
	end
end

function screen.draw()
	draw.background()
	local on, total = 0, 0
	for _, sys in ipairs(app.library or {}) do
		if sys.platform then
			total = total + 1
			if settings.isSelected(sys.name) then
				on = on + 1
			end
		end
	end
	draw.header("Systems", string.format("%d of %d selected", on, total))
	list:draw()
	draw.footer({ { "A", "Toggle" }, { "X", "All" }, { "Y", "None" }, { "B", "Back" } })
end

return screen
