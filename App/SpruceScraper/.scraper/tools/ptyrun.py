"""Run a command on a pseudo-terminal and copy its output to stdout as it comes.

Skyscraper prints progress with printf() and does not flush; through a pipe that output arrives
in 8 KB blocks, a few dozen games at a time. On a terminal stdout is line-buffered, so every
game shows up as it finishes. Prints "@@PID <pid>" first and "@@EXIT <code>" last. SIGINT and
SIGTERM are passed on to the command; stdin is /dev/null so nothing can wait for input.

    python3 ptyrun.py <program> [args...]

Runs on spruce's bundled python3.10 (get_python_path: spruce/flip/bin/python3.10), whose
libpython has termios, select and fcntl built in.
"""
import os
import pty
import signal
import sys


def main(argv):
    if not argv:
        sys.stdout.write("@@EXIT 127\n")
        return 127
    pid, fd = pty.fork()
    if pid == 0:
        try:
            null = os.open(os.devnull, os.O_RDONLY)
            os.dup2(null, 0)
            os.execvp(argv[0], argv)
        except OSError as exc:
            os.write(2, ("cannot run %s: %s\n" % (argv[0], exc)).encode())
        os._exit(127)

    out = sys.stdout.buffer
    out.write(b"@@PID %d\n" % pid)
    out.flush()

    def forward(signum, _frame):
        try:
            os.kill(pid, signum)
        except OSError:
            pass

    signal.signal(signal.SIGINT, forward)
    signal.signal(signal.SIGTERM, forward)

    while True:
        try:
            data = os.read(fd, 4096)
        except OSError:
            break  # EIO: the program closed the terminal
        if not data:
            break
        out.write(data)
        out.flush()

    _, status = os.waitpid(pid, 0)
    if os.WIFEXITED(status):
        code = os.WEXITSTATUS(status)
    else:
        code = 128 + os.WTERMSIG(status)
    out.write(b"\n@@EXIT %d\n" % code)
    out.flush()
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
