--- The environment Skyscraper runs with (the worker passes it to every run)
local skyenv = {}

--- paths: env.lua's table; home: Skyscraper's HOME; fs: scraper.fsys or a test double.
--- The glibc 2.33 build carries no libraries and needs only what every board's firmware has, so it
--- gets an empty LD_LIBRARY_PATH: no card directory on spruce's path can shadow a firmware library.
--- A bundle with a lib/ folder (the interim one) runs on that plus spruce's path, as before.
function skyenv.build(paths, home, fs)
	local ld = ""
	if fs.isDir(paths.skyscraper .. "/lib") then
		ld = paths.skyscraper .. "/lib"
		if paths.baseLibraryPath and paths.baseLibraryPath ~= "" then
			ld = ld .. ":" .. paths.baseLibraryPath
		end
	end
	local env = {
		"HOME=" .. home,
		"LD_LIBRARY_PATH=" .. ld,
		"QT_PLUGIN_PATH=" .. paths.skyscraper .. "/plugins",
		"NO_COLOR=1",
		"LANG=C.UTF-8",
		"LC_ALL=C.UTF-8",
	}
	-- firmware may hold no CA certificates; the 2.33 build reads spruce's bundle from SSL_CERT_FILE
	if paths.caFile and fs.isFile(paths.caFile) then
		env[#env + 1] = "SSL_CERT_FILE=" .. paths.caFile
	end
	return env
end

return skyenv
