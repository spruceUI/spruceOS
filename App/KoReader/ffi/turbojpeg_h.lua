local ffi = require("ffi")

ffi.cdef[[
enum TJINIT {
  TJINIT_COMPRESS = 0,
  TJINIT_DECOMPRESS = 1,
  TJINIT_TRANSFORM = 2,
};
enum TJSAMP {
  TJSAMP_444 = 0,
  TJSAMP_422 = 1,
  TJSAMP_420 = 2,
  TJSAMP_GRAY = 3,
  TJSAMP_440 = 4,
  TJSAMP_411 = 5,
  TJSAMP_441 = 6,
  TJSAMP_UNKNOWN = -1,
};
enum TJPF {
  TJPF_RGB = 0,
  TJPF_BGR = 1,
  TJPF_RGBX = 2,
  TJPF_BGRX = 3,
  TJPF_XBGR = 4,
  TJPF_XRGB = 5,
  TJPF_GRAY = 6,
  TJPF_RGBA = 7,
  TJPF_BGRA = 8,
  TJPF_ABGR = 9,
  TJPF_ARGB = 10,
  TJPF_CMYK = 11,
  TJPF_UNKNOWN = -1,
};
enum TJPARAM {
  TJPARAM_STOPONWARNING = 0,
  TJPARAM_BOTTOMUP = 1,
  TJPARAM_NOREALLOC = 2,
  TJPARAM_QUALITY = 3,
  TJPARAM_SUBSAMP = 4,
  TJPARAM_JPEGWIDTH = 5,
  TJPARAM_JPEGHEIGHT = 6,
  TJPARAM_PRECISION = 7,
  TJPARAM_COLORSPACE = 8,
  TJPARAM_FASTUPSAMPLE = 9,
  TJPARAM_FASTDCT = 10,
  TJPARAM_OPTIMIZE = 11,
  TJPARAM_PROGRESSIVE = 12,
  TJPARAM_SCANLIMIT = 13,
  TJPARAM_ARITHMETIC = 14,
  TJPARAM_LOSSLESS = 15,
  TJPARAM_LOSSLESSPSV = 16,
  TJPARAM_LOSSLESSPT = 17,
  TJPARAM_RESTARTBLOCKS = 18,
  TJPARAM_RESTARTROWS = 19,
  TJPARAM_XDENSITY = 20,
  TJPARAM_YDENSITY = 21,
  TJPARAM_DENSITYUNITS = 22,
};
typedef void *tjhandle;
tjhandle tj3Init(int);
int tj3Set(tjhandle, int, int);
int tj3Get(tjhandle, int);
int tj3Compress8(tjhandle, const unsigned char *, int, int, int, int, unsigned char **, size_t *);
int tj3DecompressHeader(tjhandle, const unsigned char *, size_t);
int tj3Decompress8(tjhandle, const unsigned char *, size_t, unsigned char *, int, int);
void tj3Destroy(tjhandle);
int tj3SaveImage8(tjhandle, const char *, const unsigned char *, int, int, int, int);
void tj3Free(void *);
]]
