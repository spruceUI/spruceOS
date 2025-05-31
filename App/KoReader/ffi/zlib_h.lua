local ffi = require("ffi")

ffi.cdef[[
long unsigned int compressBound(long unsigned int);
int compress2(unsigned char *, long unsigned int *, const unsigned char *, long unsigned int, int);
long unsigned int crc32(long unsigned int, const unsigned char *, unsigned int);
int uncompress(unsigned char *, long unsigned int *, const unsigned char *, long unsigned int);
]]
