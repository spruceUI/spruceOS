local ffi = require("ffi")

ffi.cdef[[
typedef long int off_t;
typedef long int time_t;
typedef long int suseconds_t;
struct timeval {
  time_t tv_sec;
  suseconds_t tv_usec;
};
struct timespec {
  time_t tv_sec;
  long int tv_nsec;
};
struct statvfs {
  long unsigned int f_bsize;
  long unsigned int f_frsize;
  long unsigned int f_blocks;
  long unsigned int f_bfree;
  long unsigned int f_bavail;
  long unsigned int f_files;
  long unsigned int f_ffree;
  long unsigned int f_favail;
  long unsigned int f_fsid;
  long unsigned int f_flag;
  long unsigned int f_namemax;
  int __f_spare[6];
};
]]
