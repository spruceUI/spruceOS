--- The real filesystem behind the scraper/ modules' fs interface
---
--- Directory listing goes through LuaJIT FFI readdir() on Linux (every spruce device): no shell
--- quoting, any byte in a name, and d_type tells files from folders. LÖVE's own filesystem only
--- sees the game directory, and nativefs-style PhysFS mounts are global state that two threads
--- would race over. Elsewhere (a desktop LÖVE) it falls back to ls.
local util = require("scraper.util")

local fsys = {}

local ok, ffi = pcall(require, "ffi")
local useFFI = ok and ffi.os == "Linux" and (ffi.arch == "arm64" or ffi.arch == "x64")
local C

if useFFI then
	C = ffi.C
	-- glibc's LP64 struct dirent (the same on aarch64 and x86_64)
	pcall(ffi.cdef, [[
		typedef struct spruce_scraper_dir SPRUCE_SCRAPER_DIR;
		struct spruce_scraper_dirent {
			uint64_t d_ino;
			int64_t d_off;
			unsigned short d_reclen;
			unsigned char d_type;
			char d_name[256];
		};
	]])
	pcall(ffi.cdef, [[
		SPRUCE_SCRAPER_DIR *opendir(const char *name);
		struct spruce_scraper_dirent *readdir(SPRUCE_SCRAPER_DIR *dirp);
		int closedir(SPRUCE_SCRAPER_DIR *dirp);
	]])
	pcall(ffi.cdef, "int mkdir(const char *path, unsigned int mode);")
	pcall(ffi.cdef, "int rmdir(const char *path);")
	pcall(ffi.cdef, "int unlink(const char *path);")
end

local DT_UNKNOWN, DT_DIR, DT_REG, DT_LNK = 0, 4, 8, 10

function fsys.isDir(path)
	if useFFI then
		local d = C.opendir(path)
		if d ~= nil then
			C.closedir(d)
			return true
		end
		return false
	end
	return util.executeOk(os.execute("test -d " .. util.shellQuote(path)))
end

function fsys.isFile(path)
	local f = io.open(path, "rb")
	if not f then
		return false
	end
	f:close()
	return not fsys.isDir(path)
end

--- { { name = "x", isDir = bool }, ... } or nil when path is not a readable folder
function fsys.list(path)
	if useFFI then
		local d = C.opendir(path)
		if d == nil then
			return nil
		end
		local out = {}
		while true do
			local e = C.readdir(d)
			if e == nil then
				break
			end
			local name = ffi.string(e.d_name)
			if name ~= "." and name ~= ".." then
				local t = e.d_type
				local isDir
				if t == DT_DIR then
					isDir = true
				elseif t == DT_REG then
					isDir = false
				elseif t == DT_UNKNOWN or t == DT_LNK then
					isDir = fsys.isDir(path .. "/" .. name)
				else
					isDir = false
				end
				out[#out + 1] = { name = name, isDir = isDir }
			end
		end
		C.closedir(d)
		return out
	end
	local p = io.popen("ls -1Ap " .. util.shellQuote(path) .. " 2>/dev/null")
	if not p then
		return nil
	end
	local out = {}
	for line in p:lines() do
		if line:sub(-1) == "/" then
			out[#out + 1] = { name = line:sub(1, -2), isDir = true }
		elseif line ~= "" then
			out[#out + 1] = { name = line, isDir = false }
		end
	end
	p:close()
	if #out == 0 and not fsys.isDir(path) then
		return nil
	end
	return out
end

function fsys.read(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local data = f:read("*a")
	f:close()
	return data
end

--- Write through a temporary file and rename, so a crash never leaves half a file behind
function fsys.write(path, data)
	local tmp = path .. ".part"
	local f, err = io.open(tmp, "wb")
	if not f then
		return false, err
	end
	local okWrite, werr = f:write(data)
	f:close()
	if not okWrite then
		os.remove(tmp)
		return false, werr
	end
	local okRename, rerr = os.rename(tmp, path)
	if not okRename then
		os.remove(tmp)
		return false, rerr
	end
	return true
end

function fsys.mkdirs(path)
	if fsys.isDir(path) then
		return true
	end
	local prefix = path:sub(1, 1) == "/" and "/" or ""
	for part in path:gmatch("[^/]+") do
		prefix = prefix .. part
		if useFFI then
			C.mkdir(prefix, 493) -- 0755; EEXIST is fine
		elseif not fsys.isDir(prefix) then
			os.execute("mkdir " .. util.shellQuote(prefix))
		end
		prefix = prefix .. "/"
	end
	return fsys.isDir(path)
end

local function copyFile(src, dst)
	local input = io.open(src, "rb")
	if not input then
		return false, "cannot read " .. src
	end
	local tmp = dst .. ".part"
	local output, err = io.open(tmp, "wb")
	if not output then
		input:close()
		return false, err
	end
	while true do
		local chunk = input:read(65536)
		if not chunk then
			break
		end
		if not output:write(chunk) then
			input:close()
			output:close()
			os.remove(tmp)
			return false, "write failed (card full?)"
		end
	end
	input:close()
	output:close()
	local okRename, rerr = os.rename(tmp, dst)
	if not okRename then
		os.remove(tmp)
		return false, rerr
	end
	return true
end

--- Rename, or copy and delete when src and dst are on different cards
function fsys.move(src, dst)
	if os.rename(src, dst) then
		return true
	end
	local okCopy, err = copyFile(src, dst)
	if not okCopy then
		return false, err
	end
	os.remove(src)
	return true
end

function fsys.remove(path)
	return os.remove(path) ~= nil
end

--- Delete a folder tree. Refuses anything outside the scraper's own data folder.
function fsys.removeTree(path, guard)
	guard = guard or fsys.guard
	if not guard or path:sub(1, #guard + 1) ~= guard .. "/" then
		return false, "refusing to delete " .. path
	end
	local entries = fsys.list(path)
	if not entries then
		os.remove(path)
		return true
	end
	for _, e in ipairs(entries) do
		local child = path .. "/" .. e.name
		if e.isDir then
			fsys.removeTree(child, guard)
		else
			os.remove(child)
		end
	end
	if useFFI then
		C.rmdir(path)
	else
		os.remove(path)
	end
	return true
end

--- Folder removeTree may delete inside (the app's userdata); set once by the worker
function fsys.setGuard(path)
	fsys.guard = path
end

return fsys
