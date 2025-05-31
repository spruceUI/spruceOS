local ffi = require("ffi")

ffi.cdef[[
static const int UPDATE_MODE_PARTIAL = 0;
static const int UPDATE_MODE_FULL = 1;
static const int WAVEFORM_MODE_INIT = 0;
static const int WAVEFORM_MODE_DU = 1;
static const int WAVEFORM_MODE_GC16 = 2;
static const int WAVEFORM_MODE_GC4 = 2;
static const int WAVEFORM_MODE_GC16_FAST = 3;
static const int WAVEFORM_MODE_A2 = 4;
static const int WAVEFORM_MODE_GL16 = 5;
static const int WAVEFORM_MODE_GL16_FAST = 6;
static const int WAVEFORM_MODE_DU4 = 7;
static const int WAVEFORM_MODE_REAGL = 8;
static const int WAVEFORM_MODE_REAGLD = 9;
static const int WAVEFORM_MODE_GL4 = 10;
static const int WAVEFORM_MODE_GL16_INV = 11;
static const int WAVEFORM_MODE_AUTO = 257;
static const int WAVEFORM_MODE_ZELDA_GL16 = 3;
static const int WAVEFORM_MODE_ZELDA_A2 = 6;
static const int WAVEFORM_MODE_ZELDA_LAST = 7;
static const int WAVEFORM_MODE_ZELDA_REAGL = 4;
static const int WAVEFORM_MODE_ZELDA_REAGLD = 5;
static const int WAVEFORM_MODE_ZELDA_GC16_FAST = 2;
static const int WAVEFORM_MODE_ZELDA_GL16_FAST = 3;
static const int WAVEFORM_MODE_ZELDA_GLR16 = 4;
static const int WAVEFORM_MODE_ZELDA_GLD16 = 5;
static const int WAVEFORM_MODE_ZELDA_GCK16 = 8;
static const int WAVEFORM_MODE_ZELDA_GLKW16 = 9;
static const int WAVEFORM_MODE_ZELDA_GL4 = 3;
static const int WAVEFORM_MODE_ZELDA_GL16_INV = 3;
static const int TEMP_USE_AMBIENT = 4096;
static const int TEMP_USE_PAPYRUS = 4097;
static const int TEMP_USE_AUTO = 4097;
static const int TEMP_USE_ZELDA_AUTO = 4096;
static const int MXCFB_SET_TEMPERATURE = 1074021932;
static const int MXCFB_GET_TEMPERATURE = 2147763768;
static const int EPDC_FLAG_ENABLE_INVERSION = 1;
static const int EPDC_FLAG_FORCE_MONOCHROME = 2;
static const int EPDC_FLAG_USE_CMAP = 4;
static const int EPDC_FLAG_USE_ALT_BUFFER = 256;
static const int EPDC_FLAG_TEST_COLLISION = 512;
static const int EPDC_FLAG_GROUP_UPDATE = 1024;
static const int EPDC_FLAG_FORCE_Y2 = 2048;
static const int EPDC_FLAG_USE_REAGLD = 4096;
static const int EPDC_FLAG_USE_DITHERING_Y1 = 8192;
static const int EPDC_FLAG_USE_DITHERING_Y2 = 16384;
static const int EPDC_FLAG_USE_DITHERING_Y4 = 32768;
static const int EPDC_FLAG_USE_ZELDA_DITHERING_Y4 = 16384;
static const int EPDC_FLAG_USE_ZELDA_REGAL = 32768;
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
struct mxcfb_alt_buffer_data {
  uint32_t phys_addr;
  uint32_t width;
  uint32_t height;
  struct mxcfb_rect alt_update_region;
};
struct mxcfb_update_data {
  struct mxcfb_rect update_region;
  uint32_t waveform_mode;
  uint32_t update_mode;
  uint32_t update_marker;
  uint32_t hist_bw_waveform_mode;
  uint32_t hist_gray_waveform_mode;
  int temp;
  unsigned int flags;
  struct mxcfb_alt_buffer_data alt_buffer_data;
};
struct mxcfb_update_data_zelda {
  struct mxcfb_rect update_region;
  uint32_t waveform_mode;
  uint32_t update_mode;
  uint32_t update_marker;
  int temp;
  unsigned int flags;
  int dither_mode;
  int quant_bit;
  struct mxcfb_alt_buffer_data alt_buffer_data;
  uint32_t hist_bw_waveform_mode;
  uint32_t hist_gray_waveform_mode;
  uint32_t ts_pxp;
  uint32_t ts_epdc;
};
struct mxcfb_update_data_rex {
  struct mxcfb_rect update_region;
  uint32_t waveform_mode;
  uint32_t update_mode;
  uint32_t update_marker;
  int temp;
  unsigned int flags;
  int dither_mode;
  int quant_bit;
  struct mxcfb_alt_buffer_data alt_buffer_data;
  uint32_t hist_bw_waveform_mode;
  uint32_t hist_gray_waveform_mode;
};
static const int MXCFB_SEND_UPDATE = 1078478382;
static const int MXCFB_SEND_UPDATE_ZELDA = 1079526958;
static const int MXCFB_SEND_UPDATE_REX = 1079002670;
struct mxcfb_update_marker_data {
  uint32_t update_marker;
  uint32_t collision_test;
};
static const int MXCFB_WAIT_FOR_UPDATE_COMPLETE = 3221767727;
static const int MXCFB_WAIT_FOR_UPDATE_COMPLETE_PEARL = 1074021935;
static const int MXCFB_WAIT_FOR_UPDATE_SUBMISSION = 1074021943;
static const int NIGHTMODE_STRIDE_DEFAULT = 16;
static const int NIGHTMODE_STRIDE_DEFAULT_REX = 138;
struct mxcfb_nightmode_ctrl {
  int disable;
  int start;
  int stride;
  int current_level;
};
static const int MXCFB_SET_NIGHTMODE = 2147763786;
static const int MTK_EPDC_FLAG_USE_DITHERING_Y4 = 16384;
static const int MTK_EPDC_FLAG_USE_REGAL = 32768;
static const int MTK_EPDC_FLAG_ENABLE_SWIPE = 65536;
static const int MTK_WAVEFORM_MODE_INIT = 0;
static const int MTK_WAVEFORM_MODE_DU = 1;
static const int MTK_WAVEFORM_MODE_GC16 = 2;
static const int MTK_WAVEFORM_MODE_GC16_FAST = 2;
static const int MTK_WAVEFORM_MODE_GL16 = 3;
static const int MTK_WAVEFORM_MODE_GL16_FAST = 3;
static const int MTK_WAVEFORM_MODE_GL4 = 3;
static const int MTK_WAVEFORM_MODE_GL16_INV = 3;
static const int MTK_WAVEFORM_MODE_GLR16 = 4;
static const int MTK_WAVEFORM_MODE_REAGL = 4;
static const int MTK_WAVEFORM_MODE_GLD16 = 5;
static const int MTK_WAVEFORM_MODE_REAGLD = 5;
static const int MTK_WAVEFORM_MODE_A2 = 6;
static const int MTK_WAVEFORM_MODE_DU4 = 7;
static const int MTK_WAVEFORM_MODE_LAST = 7;
static const int MTK_WAVEFORM_MODE_GCK16 = 8;
static const int MTK_WAVEFORM_MODE_GLKW16 = 9;
static const int MTK_WAVEFORM_MODE_GC16_PARTIAL = 10;
static const int MTK_WAVEFORM_MODE_GCK16_PARTIAL = 11;
static const int MTK_WAVEFORM_MODE_DUNM = 12;
static const int MTK_WAVEFORM_MODE_P2SW = 13;
enum MTK_SWIPE_DIRECTION_ENUM {
  MTK_SWIPE_DOWN = 0,
  MTK_SWIPE_UP = 1,
  MTK_SWIPE_LEFT = 2,
  MTK_SWIPE_RIGHT = 3,
  MTK_SWIPE_MAX = 4,
};
struct mxcfb_swipe_data {
  uint32_t direction;
  uint32_t steps;
};
struct mxcfb_update_data_mtk {
  struct mxcfb_rect update_region;
  uint32_t waveform_mode;
  uint32_t update_mode;
  uint32_t update_marker;
  int temp;
  unsigned int flags;
  int dither_mode;
  int quant_bit;
  struct mxcfb_alt_buffer_data alt_buffer_data;
  struct mxcfb_swipe_data swipe_data;
  uint32_t hist_bw_waveform_mode;
  uint32_t hist_gray_waveform_mode;
  uint32_t ts_pxp;
  uint32_t ts_epdc;
};
struct mxcfb_panel_info {
  char wf_file_name[100];
  int vcom_value;
  int temp;
  int temp_zone;
};
struct mxcfb_halftone_data {
  struct mxcfb_rect region[2];
  int halftone_mode;
};
typedef union {
  uint32_t flag;
  uint32_t markers[64];
} mxcfb_markers_data;
static const int UPDATE_FLAGS_FAST_MODE = -2147483648;
static const int UPDATE_FLAGS_MODE_FAST_FLAG = 1;
static const int MXCFB_SEND_UPDATE_MTK = 1080051246;
static const int MXCFB_SET_NIGHTMODE_MTK = 2148550218;
static const int MXCFB_GET_PANEL_INFO_MTK = 2154841904;
static const int MXCFB_SET_HALFTONE_MTK = 1076119115;
static const int MXCFB_WAIT_FOR_ANY_UPDATE_COMPLETE_MTK = 3221505591;
static const int MXCFB_SET_UPDATE_FLAGS_MTK = 1074021947;
static const int MXCFB_GET_UPDATE_FLAGS_MTK = 3221505596;
]]
