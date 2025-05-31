local ffi = require("ffi")

ffi.cdef[[
static const int IN_ACCESS = 1;
static const int IN_ATTRIB = 4;
static const int IN_CLOSE_WRITE = 8;
static const int IN_CLOSE_NOWRITE = 16;
static const int IN_CREATE = 256;
static const int IN_DELETE = 512;
static const int IN_DELETE_SELF = 1024;
static const int IN_MODIFY = 2;
static const int IN_MOVE_SELF = 2048;
static const int IN_MOVED_FROM = 64;
static const int IN_MOVED_TO = 128;
static const int IN_OPEN = 32;
static const int IN_ALL_EVENTS = 4095;
static const int IN_MOVE = 192;
static const int IN_CLOSE = 24;
static const int IN_DONT_FOLLOW = 33554432;
static const int IN_EXCL_UNLINK = 67108864;
static const int IN_MASK_ADD = 536870912;
static const int IN_ONESHOT = 2147483648;
static const int IN_ONLYDIR = 16777216;
static const int IN_IGNORED = 32768;
static const int IN_ISDIR = 1073741824;
static const int IN_Q_OVERFLOW = 16384;
static const int IN_UNMOUNT = 8192;
static const int IN_NONBLOCK = 2048;
static const int IN_CLOEXEC = 524288;
int inotify_init(void) __attribute__((nothrow, leaf));
int inotify_init1(int) __attribute__((nothrow, leaf));
int inotify_add_watch(int, const char *, uint32_t) __attribute__((nothrow, leaf));
int inotify_rm_watch(int, int) __attribute__((nothrow, leaf));
struct inotify_event {
  int wd;
  uint32_t mask;
  uint32_t cookie;
  uint32_t len;
  char name[];
};
]]
