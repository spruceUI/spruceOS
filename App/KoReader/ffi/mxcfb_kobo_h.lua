local ffi = require("ffi")

ffi.cdef[[
static const int UPDATE_MODE_PARTIAL = 0;
static const int UPDATE_MODE_FULL = 1;
static const int WAVEFORM_MODE_INIT = 0;
static const int WAVEFORM_MODE_DU = 1;
static const int WAVEFORM_MODE_GC16 = 2;
static const int WAVEFORM_MODE_GC4 = 3;
static const int WAVEFORM_MODE_A2 = 4;
static const int WAVEFORM_MODE_GL16 = 5;
static const int WAVEFORM_MODE_REAGL = 6;
static const int WAVEFORM_MODE_REAGLD = 7;
static const int WAVEFORM_MODE_DU4 = 8;
static const int WAVEFORM_MODE_GCK16 = 9;
static const int WAVEFORM_MODE_GLKW16 = 10;
static const int WAVEFORM_MODE_AUTO = 257;
static const int TEMP_USE_AMBIENT = 4096;
static const int EPDC_FLAG_ENABLE_INVERSION = 1;
static const int EPDC_FLAG_FORCE_MONOCHROME = 2;
static const int EPDC_FLAG_USE_CMAP = 4;
static const int EPDC_FLAG_USE_ALT_BUFFER = 256;
static const int EPDC_FLAG_USE_AAD = 4096;
static const int EPDC_FLAG_TEST_COLLISION = 512;
static const int EPDC_FLAG_GROUP_UPDATE = 1024;
static const int EPDC_FLAG_USE_DITHERING_Y1 = 8192;
static const int EPDC_FLAG_USE_DITHERING_Y4 = 16384;
static const int EPDC_FLAG_USE_REGAL = 32768;
static const int EPDC_FLAG_USE_DITHERING_NTX_D8 = 1048576;
enum mxcfb_dithering_mode {
  EPDC_FLAG_USE_DITHERING_PASSTHROUGH = 0,
  EPDC_FLAG_USE_DITHERING_FLOYD_STEINBERG = 1,
  EPDC_FLAG_USE_DITHERING_ATKINSON = 2,
  EPDC_FLAG_USE_DITHERING_ORDERED = 3,
  EPDC_FLAG_USE_DITHERING_QUANT_ONLY = 4,
  EPDC_FLAG_USE_DITHERING_MAX = 5,
};
struct mxcfb_rect {
  uint32_t top;
  uint32_t left;
  uint32_t width;
  uint32_t height;
};
struct mxcfb_alt_buffer_data_ntx {
  void *virt_addr;
  uint32_t phys_addr;
  uint32_t width;
  uint32_t height;
  struct mxcfb_rect alt_update_region;
};
struct mxcfb_update_data_v1_ntx {
  struct mxcfb_rect update_region;
  uint32_t waveform_mode;
  uint32_t update_mode;
  uint32_t update_marker;
  int temp;
  unsigned int flags;
  struct mxcfb_alt_buffer_data_ntx alt_buffer_data;
};
struct mxcfb_alt_buffer_data {
  uint32_t phys_addr;
  uint32_t width;
  uint32_t height;
  struct mxcfb_rect alt_update_region;
};
struct mxcfb_update_data_v1 {
  struct mxcfb_rect update_region;
  uint32_t waveform_mode;
  uint32_t update_mode;
  uint32_t update_marker;
  int temp;
  unsigned int flags;
  struct mxcfb_alt_buffer_data alt_buffer_data;
};
struct mxcfb_update_data_v2 {
  struct mxcfb_rect update_region;
  uint32_t waveform_mode;
  uint32_t update_mode;
  uint32_t update_marker;
  int temp;
  unsigned int flags;
  int dither_mode;
  int quant_bit;
  struct mxcfb_alt_buffer_data alt_buffer_data;
};
struct mxcfb_update_marker_data {
  uint32_t update_marker;
  uint32_t collision_test;
};
static const int MXCFB_SEND_UPDATE_V1_NTX = 1078216238;
static const int MXCFB_WAIT_FOR_UPDATE_COMPLETE_V1 = 1074021935;
static const int MXCFB_SEND_UPDATE_V1 = 1077954094;
static const int MXCFB_SEND_UPDATE_V2 = 1078478382;
static const int MXCFB_WAIT_FOR_UPDATE_COMPLETE_V3 = 3221767727;
static const int MXCFB_SET_PWRDOWN_DELAY = 1074021936;
static const int MXCFB_GET_PWRDOWN_DELAY = 2147763761;
static const int HWTCON_FLAG_USE_DITHERING = 1;
static const int HWTCON_FLAG_FORCE_A2_OUTPUT = 16;
static const int HWTCON_FLAG_FORCE_A2_OUTPUT_WHITE = 32;
static const int HWTCON_FLAG_FORCE_A2_OUTPUT_BLACK = 64;
static const int TEMP_USE_SENSOR = 1048576;
enum HWTCON_WAVEFORM_MODE_ENUM {
  HWTCON_WAVEFORM_MODE_INIT = 0,
  HWTCON_WAVEFORM_MODE_DU = 1,
  HWTCON_WAVEFORM_MODE_GC16 = 2,
  HWTCON_WAVEFORM_MODE_GL16 = 3,
  HWTCON_WAVEFORM_MODE_GLR16 = 4,
  HWTCON_WAVEFORM_MODE_REAGL = 4,
  HWTCON_WAVEFORM_MODE_A2 = 6,
  HWTCON_WAVEFORM_MODE_GCK16 = 8,
  HWTCON_WAVEFORM_MODE_GLKW16 = 9,
  HWTCON_WAVEFORM_MODE_AUTO = 257,
};
enum hwtcon_dithering_mode {
  HWTCON_FLAG_USE_DITHERING_Y8_Y4_Q = 256,
  HWTCON_FLAG_USE_DITHERING_Y8_Y2_Q = 512,
  HWTCON_FLAG_USE_DITHERING_Y8_Y1_Q = 768,
  HWTCON_FLAG_USE_DITHERING_Y4_Y2_Q = 66048,
  HWTCON_FLAG_USE_DITHERING_Y4_Y1_Q = 66304,
  HWTCON_FLAG_USE_DITHERING_Y8_Y4_B = 257,
  HWTCON_FLAG_USE_DITHERING_Y8_Y2_B = 513,
  HWTCON_FLAG_USE_DITHERING_Y8_Y1_B = 769,
  HWTCON_FLAG_USE_DITHERING_Y4_Y2_B = 66049,
  HWTCON_FLAG_USE_DITHERING_Y4_Y1_B = 66305,
  HWTCON_FLAG_USE_DITHERING_Y8_Y4_S = 258,
  HWTCON_FLAG_USE_DITHERING_Y8_Y2_S = 514,
  HWTCON_FLAG_USE_DITHERING_Y8_Y1_S = 770,
  HWTCON_FLAG_USE_DITHERING_Y4_Y2_S = 66050,
  HWTCON_FLAG_USE_DITHERING_Y4_Y1_S = 66306,
};
struct hwtcon_rect {
  uint32_t top;
  uint32_t left;
  uint32_t width;
  uint32_t height;
};
struct hwtcon_update_marker_data {
  uint32_t update_marker;
  uint32_t collision_test;
};
struct hwtcon_update_data {
  struct hwtcon_rect update_region;
  uint32_t waveform_mode;
  uint32_t update_mode;
  uint32_t update_marker;
  unsigned int flags;
  int dither_mode;
};
static const int HWTCON_SET_TEMPERATURE = 1074021932;
static const int HWTCON_SEND_UPDATE = 1076119086;
static const int HWTCON_WAIT_FOR_UPDATE_SUBMISSION = 1074021943;
static const int HWTCON_WAIT_FOR_UPDATE_COMPLETE = 3221767727;
]]
