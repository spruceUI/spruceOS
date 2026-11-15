--- Run Skyscraper and hand its output over line by line (worker thread only)
---
--- With spruce's python3 the program runs on a pty through tools/ptyrun.py, so its unflushed
--- printf() output arrives as each game finishes. Without it, a sh wrapper does the same framing
--- over a pipe and progress comes in bursts. Either way the output starts with "@@PID <pid>"
--- (the program itself, so Stop can SIGINT it) and ends with "@@EXIT <code>": LuaJIT's
--- popen():close() does not return the exit status.
local parser = require("scraper.parser")
local util = require("scraper.util")

local spawn = {}

-- env execs the program, so $! is Skyscraper itself; the bare echo ends an unterminated last line
local SH_RUNNER = '"$@" </dev/null & p=$!; echo "@@PID $p"; wait "$p"; c=$?; echo; echo "@@EXIT $c"'

--- True when this python can run tools/ptyrun.py
function spawn.pythonWorks(python)
	if not python or python == "" then
		return false
	end
	local cmd = util.shellQuote(python) .. " -c 'import os, pty, select, signal' >/dev/null 2>&1"
	return util.executeOk(os.execute(cmd))
end

--- opts: env (array of "KEY=value" for the program only), cwd, python, ptyrun,
---       onPid(pid or nil), onLine(line). Returns the exit code, or nil when nothing ran.
function spawn.run(argv, opts)
	local program = { "env" }
	for _, kv in ipairs(opts.env or {}) do
		program[#program + 1] = kv
	end
	for _, a in ipairs(argv) do
		program[#program + 1] = a
	end
	local runner
	if opts.python then
		runner = util.shellQuote(opts.python) .. " -u " .. util.shellQuote(opts.ptyrun) .. " " .. util.shellJoin(program)
	else
		runner = "sh -c " .. util.shellQuote(SH_RUNNER) .. " sh " .. util.shellJoin(program)
	end
	local cmd = "cd " .. util.shellQuote(opts.cwd or "/") .. " && " .. runner .. " 2>&1"
	local p = io.popen(cmd, "r")
	if not p then
		return nil
	end
	local exitCode
	for line in p:lines() do
		local what, value = parser.control(line)
		if what == "pid" then
			if opts.onPid then
				opts.onPid(value)
			end
		elseif what == "exit" then
			exitCode = value
		else
			-- a pty ends lines in "\r\n", and Skyscraper's "Response delayed" status ends in a bare
			-- "\r" that would glue it to the next game's line: every piece is a line
			for piece in line:gmatch("[^\r]+") do
				opts.onLine(piece)
			end
		end
	end
	p:close()
	if opts.onPid then
		opts.onPid(nil)
	end
	return exitCode
end

function spawn.interrupt(pid)
	if pid then
		os.execute("kill -INT " .. tostring(math.floor(pid)) .. " 2>/dev/null")
	end
end

return spawn
