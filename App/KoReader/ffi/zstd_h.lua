local ffi = require("ffi")

ffi.cdef[[
unsigned int ZSTD_versionNumber(void) __attribute__((visibility("default")));
const char *ZSTD_versionString(void) __attribute__((visibility("default")));
static const int ZSTD_CLEVEL_DEFAULT = 3;
size_t ZSTD_compress(void *, size_t, const void *, size_t, int) __attribute__((visibility("default")));
size_t ZSTD_decompress(void *, size_t, const void *, size_t) __attribute__((visibility("default")));
static const int ZSTD_CONTENTSIZE_UNKNOWN = -1;
static const int ZSTD_CONTENTSIZE_ERROR = -2;
long long unsigned int ZSTD_getFrameContentSize(const void *, size_t) __attribute__((visibility("default")));
size_t ZSTD_findFrameCompressedSize(const void *, size_t) __attribute__((visibility("default")));
size_t ZSTD_compressBound(size_t) __attribute__((visibility("default")));
unsigned int ZSTD_isError(size_t) __attribute__((visibility("default")));
const char *ZSTD_getErrorName(size_t) __attribute__((visibility("default")));
int ZSTD_minCLevel(void) __attribute__((visibility("default")));
int ZSTD_maxCLevel(void) __attribute__((visibility("default")));
struct ZSTD_CCtx_s;
typedef struct ZSTD_CCtx_s ZSTD_CCtx;
ZSTD_CCtx *ZSTD_createCCtx(void) __attribute__((visibility("default")));
size_t ZSTD_freeCCtx(ZSTD_CCtx *) __attribute__((visibility("default")));
size_t ZSTD_compressCCtx(ZSTD_CCtx *, void *, size_t, const void *, size_t, int) __attribute__((visibility("default")));
struct ZSTD_DCtx_s;
typedef struct ZSTD_DCtx_s ZSTD_DCtx;
ZSTD_DCtx *ZSTD_createDCtx(void) __attribute__((visibility("default")));
size_t ZSTD_freeDCtx(ZSTD_DCtx *) __attribute__((visibility("default")));
size_t ZSTD_decompressDCtx(ZSTD_DCtx *, void *, size_t, const void *, size_t) __attribute__((visibility("default")));
typedef enum {
  ZSTD_fast = 1,
  ZSTD_dfast = 2,
  ZSTD_greedy = 3,
  ZSTD_lazy = 4,
  ZSTD_lazy2 = 5,
  ZSTD_btlazy2 = 6,
  ZSTD_btopt = 7,
  ZSTD_btultra = 8,
  ZSTD_btultra2 = 9,
} ZSTD_strategy;
typedef enum {
  ZSTD_c_compressionLevel = 100,
  ZSTD_c_windowLog = 101,
  ZSTD_c_hashLog = 102,
  ZSTD_c_chainLog = 103,
  ZSTD_c_searchLog = 104,
  ZSTD_c_minMatch = 105,
  ZSTD_c_targetLength = 106,
  ZSTD_c_strategy = 107,
  ZSTD_c_enableLongDistanceMatching = 160,
  ZSTD_c_ldmHashLog = 161,
  ZSTD_c_ldmMinMatch = 162,
  ZSTD_c_ldmBucketSizeLog = 163,
  ZSTD_c_ldmHashRateLog = 164,
  ZSTD_c_contentSizeFlag = 200,
  ZSTD_c_checksumFlag = 201,
  ZSTD_c_dictIDFlag = 202,
  ZSTD_c_nbWorkers = 400,
  ZSTD_c_jobSize = 401,
  ZSTD_c_overlapLog = 402,
  ZSTD_c_experimentalParam1 = 500,
  ZSTD_c_experimentalParam2 = 10,
  ZSTD_c_experimentalParam3 = 1000,
  ZSTD_c_experimentalParam4 = 1001,
  ZSTD_c_experimentalParam5 = 1002,
  ZSTD_c_experimentalParam6 = 1003,
  ZSTD_c_experimentalParam7 = 1004,
  ZSTD_c_experimentalParam8 = 1005,
  ZSTD_c_experimentalParam9 = 1006,
  ZSTD_c_experimentalParam10 = 1007,
  ZSTD_c_experimentalParam11 = 1008,
  ZSTD_c_experimentalParam12 = 1009,
  ZSTD_c_experimentalParam13 = 1010,
  ZSTD_c_experimentalParam14 = 1011,
  ZSTD_c_experimentalParam15 = 1012,
  ZSTD_c_experimentalParam16 = 1013,
  ZSTD_c_experimentalParam17 = 1014,
  ZSTD_c_experimentalParam18 = 1015,
  ZSTD_c_experimentalParam19 = 1016,
} ZSTD_cParameter;
typedef struct {
  size_t error;
  int lowerBound;
  int upperBound;
} ZSTD_bounds;
ZSTD_bounds ZSTD_cParam_getBounds(ZSTD_cParameter) __attribute__((visibility("default")));
size_t ZSTD_CCtx_setParameter(ZSTD_CCtx *, ZSTD_cParameter, int) __attribute__((visibility("default")));
size_t ZSTD_CCtx_setPledgedSrcSize(ZSTD_CCtx *, long long unsigned int) __attribute__((visibility("default")));
typedef enum {
  ZSTD_reset_session_only = 1,
  ZSTD_reset_parameters = 2,
  ZSTD_reset_session_and_parameters = 3,
} ZSTD_ResetDirective;
size_t ZSTD_CCtx_reset(ZSTD_CCtx *, ZSTD_ResetDirective) __attribute__((visibility("default")));
size_t ZSTD_compress2(ZSTD_CCtx *, void *, size_t, const void *, size_t) __attribute__((visibility("default")));
typedef enum {
  ZSTD_d_windowLogMax = 100,
  ZSTD_d_experimentalParam1 = 1000,
  ZSTD_d_experimentalParam2 = 1001,
  ZSTD_d_experimentalParam3 = 1002,
  ZSTD_d_experimentalParam4 = 1003,
  ZSTD_d_experimentalParam5 = 1004,
} ZSTD_dParameter;
ZSTD_bounds ZSTD_dParam_getBounds(ZSTD_dParameter) __attribute__((visibility("default")));
size_t ZSTD_DCtx_setParameter(ZSTD_DCtx *, ZSTD_dParameter, int) __attribute__((visibility("default")));
size_t ZSTD_DCtx_reset(ZSTD_DCtx *, ZSTD_ResetDirective) __attribute__((visibility("default")));
struct ZSTD_inBuffer_s {
  const void *src;
  size_t size;
  size_t pos;
};
typedef struct ZSTD_inBuffer_s ZSTD_inBuffer;
struct ZSTD_outBuffer_s {
  void *dst;
  size_t size;
  size_t pos;
};
typedef struct ZSTD_outBuffer_s ZSTD_outBuffer;
typedef enum {
  ZSTD_e_continue = 0,
  ZSTD_e_flush = 1,
  ZSTD_e_end = 2,
} ZSTD_EndDirective;
size_t ZSTD_compressStream2(ZSTD_CCtx *, ZSTD_outBuffer *, ZSTD_inBuffer *, ZSTD_EndDirective) __attribute__((visibility("default")));
size_t ZSTD_CStreamInSize(void) __attribute__((visibility("default")));
size_t ZSTD_CStreamOutSize(void) __attribute__((visibility("default")));
size_t ZSTD_decompressStream(struct ZSTD_DCtx_s *, ZSTD_outBuffer *, ZSTD_inBuffer *) __attribute__((visibility("default")));
size_t ZSTD_DStreamInSize(void) __attribute__((visibility("default")));
size_t ZSTD_DStreamOutSize(void) __attribute__((visibility("default")));
size_t ZSTD_compress_usingDict(ZSTD_CCtx *, void *, size_t, const void *, size_t, const void *, size_t, int) __attribute__((visibility("default")));
size_t ZSTD_decompress_usingDict(ZSTD_DCtx *, void *, size_t, const void *, size_t, const void *, size_t) __attribute__((visibility("default")));
struct ZSTD_CDict_s;
typedef struct ZSTD_CDict_s ZSTD_CDict;
ZSTD_CDict *ZSTD_createCDict(const void *, size_t, int) __attribute__((visibility("default")));
size_t ZSTD_freeCDict(ZSTD_CDict *) __attribute__((visibility("default")));
size_t ZSTD_compress_usingCDict(ZSTD_CCtx *, void *, size_t, const void *, size_t, const ZSTD_CDict *) __attribute__((visibility("default")));
struct ZSTD_DDict_s;
typedef struct ZSTD_DDict_s ZSTD_DDict;
ZSTD_DDict *ZSTD_createDDict(const void *, size_t) __attribute__((visibility("default")));
size_t ZSTD_freeDDict(ZSTD_DDict *) __attribute__((visibility("default")));
size_t ZSTD_decompress_usingDDict(ZSTD_DCtx *, void *, size_t, const void *, size_t, const ZSTD_DDict *) __attribute__((visibility("default")));
unsigned int ZSTD_getDictID_fromDict(const void *, size_t) __attribute__((visibility("default")));
unsigned int ZSTD_getDictID_fromDDict(const ZSTD_DDict *) __attribute__((visibility("default")));
unsigned int ZSTD_getDictID_fromFrame(const void *, size_t) __attribute__((visibility("default")));
size_t ZSTD_CCtx_loadDictionary(ZSTD_CCtx *, const void *, size_t) __attribute__((visibility("default")));
size_t ZSTD_CCtx_refCDict(ZSTD_CCtx *, const ZSTD_CDict *) __attribute__((visibility("default")));
size_t ZSTD_CCtx_refPrefix(ZSTD_CCtx *, const void *, size_t) __attribute__((visibility("default")));
size_t ZSTD_DCtx_loadDictionary(ZSTD_DCtx *, const void *, size_t) __attribute__((visibility("default")));
size_t ZSTD_DCtx_refDDict(ZSTD_DCtx *, const ZSTD_DDict *) __attribute__((visibility("default")));
size_t ZSTD_DCtx_refPrefix(ZSTD_DCtx *, const void *, size_t) __attribute__((visibility("default")));
size_t ZSTD_sizeof_CCtx(const ZSTD_CCtx *) __attribute__((visibility("default")));
size_t ZSTD_sizeof_DCtx(const ZSTD_DCtx *) __attribute__((visibility("default")));
size_t ZSTD_sizeof_CDict(const ZSTD_CDict *) __attribute__((visibility("default")));
size_t ZSTD_sizeof_DDict(const ZSTD_DDict *) __attribute__((visibility("default")));
]]
