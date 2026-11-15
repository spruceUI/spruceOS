--- Physical button labels vs SDL gamepad names (from Aesthetic Spruce's src/gamepad_layout.lua)
---
--- SDL's built-in controller mappings are positional (bottom face button = "a"); most spruce
--- handhelds print Nintendo labels (A on the right). launch.sh exports SCRAPER_SWAP_AB /
--- SCRAPER_SWAP_XY per platform, the same table Aesthetic Spruce measured on the devices, so
--- "a" here always means the button labelled A.
local layout = {}

local swapAB = os.getenv("SCRAPER_SWAP_AB") == "1"
local swapXY = os.getenv("SCRAPER_SWAP_XY") == "1"

local physical = {}
if swapAB then
	physical.a, physical.b = "b", "a"
end
if swapXY then
	physical.x, physical.y = "y", "x"
end

function layout.sdlButton(name)
	return physical[name] or name
end

function layout.describe()
	return string.format("swapAB=%s swapXY=%s", tostring(swapAB), tostring(swapXY))
end

return layout
