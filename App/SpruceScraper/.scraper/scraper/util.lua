--- Small string and path helpers shared by the scraper modules (no LÖVE, no FFI)
local util = {}

function util.trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function util.startsWith(s, prefix)
	return s:sub(1, #prefix) == prefix
end

function util.split(s, sep)
	local out = {}
	local from = 1
	while true do
		local i, j = s:find(sep, from, true)
		if not i then
			out[#out + 1] = s:sub(from)
			return out
		end
		out[#out + 1] = s:sub(from, i - 1)
		from = j + 1
	end
end

function util.joinPath(...)
	local parts = {}
	for _, p in ipairs({ ... }) do
		if p ~= nil and p ~= "" then
			parts[#parts + 1] = p
		end
	end
	local joined = table.concat(parts, "/")
	return (joined:gsub("/+", "/"))
end

function util.dirname(path)
	return path:match("^(.*)/[^/]*$") or "."
end

function util.basename(path)
	return path:match("([^/]*)$")
end

--- Python's os.path.splitext: the last dot that is not leading, so ".bashrc" has no extension
function util.splitext(name)
	local lead = name:match("^%.*")
	local base, ext = name:sub(#lead + 1):match("^(.*)(%.[^%.]*)$")
	if not base then
		return name, ""
	end
	return lead .. base, ext
end

--- Qt's QFileInfo::completeBaseName: everything before the last dot (Skyscraper names media so)
function util.completeBaseName(name)
	return name:match("^(.*)%.[^%.]*$") or name
end

--- Quote one argument for /bin/sh
function util.shellQuote(s)
	return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

function util.shellJoin(argv)
	local out = {}
	for i, a in ipairs(argv) do
		out[i] = util.shellQuote(a)
	end
	return table.concat(out, " ")
end

--- Strip ANSI escape sequences (Skyscraper colours its output when it believes it is on a tty)
function util.stripAnsi(s)
	return (s:gsub("\27%[[%d;]*[A-Za-z]", ""):gsub("\r", ""))
end

--- os.execute succeeded: Lua 5.1 and plain LuaJIT return a status number, 5.2-compatible builds
--- (and the host's test runtimes) return true|nil, "exit", code
function util.executeOk(a, _, code)
	if type(a) == "number" then
		return a == 0
	end
	return a == true and (code == nil or code == 0)
end

function util.clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

function util.formatSeconds(secs)
	secs = math.max(0, math.floor(secs + 0.5))
	local h = math.floor(secs / 3600)
	local m = math.floor(secs / 60) % 60
	local s = secs % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

return util
