--- Spruce Scraper version (build.sh reads these lines)
local version = {}

version.major = 0
version.minor = 1
version.patch = 0
version.prerelease = "dev"

function version.string()
	local s = string.format("v%d.%d.%d", version.major, version.minor, version.patch)
	if version.prerelease and version.prerelease ~= "" then
		s = s .. "-" .. version.prerelease
	end
	return s
end

return version
