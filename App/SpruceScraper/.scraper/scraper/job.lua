--- UI-side handle on the worker thread (scraper/worker.lua)
local spawn = require("scraper.spawn")

local job = {}

local thread
local inbox = love.thread.getChannel("scraper_in")
local outbox = love.thread.getChannel("scraper_out")
local cancelChannel = love.thread.getChannel("scraper_cancel")

job.pid = nil
job.stoppable = false -- the run with that pid ends on Stop (a download, not the image-making run)

function job.start(paths)
	inbox:clear()
	outbox:clear()
	cancelChannel:clear()
	thread = love.thread.newThread("scraper/worker.lua")
	thread:start(paths)
end

function job.send(cmd)
	inbox:push(cmd)
end

--- Every event queued since the last call
function job.poll()
	local events = {}
	while true do
		local ev = outbox:pop()
		if ev == nil then
			break
		end
		if ev.kind == "pid" then
			job.pid = ev.pid
			job.stoppable = ev.pid ~= nil and ev.stoppable ~= false
		end
		events[#events + 1] = ev
	end
	return events
end

--- Stop: a downloading Skyscraper gets SIGINT (it finishes the games in flight and saves its
--- cache); the worker then makes and saves the images for what was downloaded and ends the job.
--- The image-making run only gets the signal with force (a second Stop): it then saves the
--- images it has made, and the rest stay in the cache for the next scrape.
function job.cancel(force)
	cancelChannel:push(true)
	if job.stoppable or force then
		spawn.interrupt(job.pid)
	end
end

function job.error()
	return thread and thread:getError()
end

function job.shutdown()
	cancelChannel:push(true)
	spawn.interrupt(job.pid)
	inbox:push({ cmd = "quit" })
end

return job
