--- Turbo.lua Signal Module
--
-- Copyright John Abrahamsen 2011, 2012, 2013 < JhnAbrhmsn@gmail.com >
--
-- "Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE."

local ffi = require "ffi"
require "turbo.cdef"
local platform = require "turbo.platform"

if ffi.arch == "mipsel" then
return {
	signal = ffi.C.sysv_signal
    -- For sigprocmask(2)
    , SIG_BLOCK   = 1
    , SIG_UNBLOCK = 2
    , SIG_SETMASK = 3
    -- Fake signal functions.
    , SIG_ERR = ffi.cast("sighandler_t", -1)    --[[ Error return.  ]]
    , SIG_DFL = ffi.cast("sighandler_t", 0) --[[ Default action.  ]]
    , SIG_IGN = ffi.cast("sighandler_t", 1) --[[ Ignore signal.  ]]   
    -- Signals.
    ,   SIGHUP  =   1   --[[ Hangup (POSIX).  ]]
    ,   SIGINT  =   2   --[[ Interrupt (ANSI).  ]]
    ,   SIGQUIT =   3   --[[ Quit (POSIX).  ]]
    ,   SIGILL  =   4   --[[ Illegal instruction (ANSI).  ]]
    ,   SIGTRAP =   5   --[[ Trace trap (POSIX).  ]]
    ,   SIGIOT  =   6   --[[ IOT trap (4.2 BSD).  ]]
    ,   SIGABRT =   SIGIOT   --[[ Abort (ANSI).  ]]
    ,   SIGBUS  =   10   --[[ BUS error (4.2 BSD).  ]]
    ,   SIGFPE  =   8   --[[ Floating-point exception (ANSI).  ]]
    ,   SIGKILL =   9   --[[ Kill, unblockable (POSIX).  ]]
    ,   SIGUSR1 =   16  --[[ User-defined signal 1 (POSIX).  ]]
    ,   SIGSEGV =   11  --[[ Segmentation violation (ANSI).  ]]
    ,   SIGUSR2 =   17  --[[ User-defined signal 2 (POSIX).  ]]
    ,   SIGPIPE =   13  --[[ Broken pipe (POSIX).  ]]
    ,   SIGALRM =   14  --[[ Alarm clock (POSIX).  ]]
    ,   SIGTERM =   15  --[[ Termination (ANSI).  ]]
    ,   SIGSTKFLT = 16  --[[ Stack fault.  ]]
    ,   SIGCLD  =   18  --[[ Same as SIGCHLD (System V).  ]]
    ,   SIGCHLD =   18  --[[ Child status has changed (POSIX).  ]]
    ,   SIGCONT =   25  --[[ Continue (POSIX).  ]]
    ,   SIGSTOP =   23  --[[ Stop, unblockable (POSIX).  ]]
    ,   SIGTSTP =   24  --[[ Keyboard stop (POSIX).  ]]
    ,   SIGTTIN =   26  --[[ Background read from tty (POSIX).  ]]
    ,   SIGTTOU =   27  --[[ Background write to tty (POSIX).  ]]
    ,   SIGURG  =   21  --[[ Urgent condition on socket (4.2 BSD).  ]]
    ,   SIGXCPU =   30  --[[ CPU limit exceeded (4.2 BSD).  ]]
    ,   SIGXFSZ =   31  --[[ File size limit exceeded (4.2 BSD).  ]]
    ,   SIGVTALRM = 28  --[[ Virtual alarm clock (4.2 BSD).  ]]
    ,   SIGPROF =   29  --[[ Profiling alarm clock (4.2 BSD).  ]]
    ,   SIGWINCH =  20  --[[ Window size change (4.3 BSD, Sun).  ]]
    ,   SIGIO =     22  --[[ I/O now possible (4.2 BSD).  ]]
    ,   SIGPOLL =   SIGIO   --[[ Pollable event occurred (System V).  ]]
    ,   SIGPWR =    19  --[[ Power failure restart (System V).  ]]
    ,   SIGSYS =    12  --[[ Bad system call.  ]]
--    ,   SIGUNUSED = 31 --[[ Not defined in MIPSEL ]]
    ,   _NSIG   =   128  --[[ Biggest signal number + 1 (including real-time signals).  ]]
	}
else
return {
        signal = ffi.C.sysv_signal
        -- For sigprocmask(2)
        , SIG_BLOCK   = 0
        , SIG_UNBLOCK = 1
        , SIG_SETMASK = 2
        -- Fake signal functions.
        , SIG_ERR = ffi.cast("sighandler_t", -1)    --[[ Error return.  ]]
        , SIG_DFL = ffi.cast("sighandler_t", 0) --[[ Default action.  ]]
        , SIG_IGN = ffi.cast("sighandler_t", 1) --[[ Ignore signal.  ]]
        -- Signals.
        ,   SIGHUP  =   1   --[[ Hangup (POSIX).  ]]
        ,   SIGINT  =   2   --[[ Interrupt (ANSI).  ]]
        ,   SIGQUIT =   3   --[[ Quit (POSIX).  ]]
        ,   SIGILL  =   4   --[[ Illegal instruction (ANSI).  ]]
        ,   SIGTRAP =   5   --[[ Trace trap (POSIX).  ]]
        ,   SIGABRT =   6   --[[ Abort (ANSI).  ]]
        ,   SIGIOT  =   6   --[[ IOT trap (4.2 BSD).  ]]
        ,   SIGBUS  =   7   --[[ BUS error (4.2 BSD).  ]]
        ,   SIGFPE  =   8   --[[ Floating-point exception (ANSI).  ]]
        ,   SIGKILL =   9   --[[ Kill, unblockable (POSIX).  ]]
        ,   SIGUSR1 =   10  --[[ User-defined signal 1 (POSIX).  ]]
        ,   SIGSEGV =   11  --[[ Segmentation violation (ANSI).  ]]
        ,   SIGUSR2 =   12  --[[ User-defined signal 2 (POSIX).  ]]
        ,   SIGPIPE =   13  --[[ Broken pipe (POSIX).  ]]
        ,   SIGALRM =   14  --[[ Alarm clock (POSIX).  ]]
        ,   SIGTERM =   15  --[[ Termination (ANSI).  ]]
        ,   SIGSTKFLT = 16  --[[ Stack fault.  ]]
        ,   SIGCLD  =   17  --[[ Same as SIGCHLD (System V).  ]]
        ,   SIGCHLD =   17  --[[ Child status has changed (POSIX).  ]]
        ,   SIGCONT =   18  --[[ Continue (POSIX).  ]]
        ,   SIGSTOP =   19  --[[ Stop, unblockable (POSIX).  ]]
        ,   SIGTSTP =   20  --[[ Keyboard stop (POSIX).  ]]
        ,   SIGTTIN =   21  --[[ Background read from tty (POSIX).  ]]
        ,   SIGTTOU =   22  --[[ Background write to tty (POSIX).  ]]
        ,   SIGURG  =   23  --[[ Urgent condition on socket (4.2 BSD).  ]]
        ,   SIGXCPU =   24  --[[ CPU limit exceeded (4.2 BSD).  ]]
        ,   SIGXFSZ =   25  --[[ File size limit exceeded (4.2 BSD).  ]]
        ,   SIGVTALRM = 26  --[[ Virtual alarm clock (4.2 BSD).  ]]
        ,   SIGPROF =   27  --[[ Profiling alarm clock (4.2 BSD).  ]]
        ,   SIGWINCH =  28  --[[ Window size change (4.3 BSD, Sun).  ]]
        ,   SIGPOLL =   29  --[[ Pollable event occurred (System V).  ]]
        ,   SIGIO =     29  --[[ I/O now possible (4.2 BSD).  ]]
        ,   SIGPWR =    30  --[[ Power failure restart (System V).  ]]
        ,   SIGSYS =    31  --[[ Bad system call.  ]]
        ,   SIGUNUSED = 31
        ,   _NSIG   =   65  --[[ Biggest signal number + 1 (including real-time signals).  ]]
    }
end
