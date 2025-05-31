local ffi = require("ffi")

ffi.cdef[[
struct area_info {
  unsigned int x_top;
  unsigned int y_top;
  unsigned int x_bottom;
  unsigned int y_bottom;
};
enum eink_update_mode {
  EINK_INIT_MODE = 1,
  EINK_DU_MODE = 2,
  EINK_GC16_MODE = 4,
  EINK_GC4_MODE = 8,
  EINK_A2_MODE = 16,
  EINK_GL16_MODE = 32,
  EINK_GLR16_MODE = 64,
  EINK_GLD16_MODE = 128,
  EINK_GU16_MODE = 132,
  EINK_GCK16_MODE = 144,
  EINK_GLK16_MODE = 148,
  EINK_CLEAR_MODE = 136,
  EINK_GC4L_MODE = 140,
  EINK_GCC16_MODE = 160,
  EINK_PARTIAL_MODE = 1024,
  EINK_AUTO_MODE = 32768,
  EINK_NEGATIVE_MODE = 65536,
  EINK_REGAL_MODE = 524288,
  EINK_GAMMA_CORRECT = 2097152,
  EINK_MONOCHROME = 4194304,
  EINK_DITHERING_Y1 = 25165824,
  EINK_DITHERING_Y4 = 41943040,
  EINK_DITHERING_SIMPLE = 75497472,
  EINK_DITHERING_NTX_Y1 = 142606336,
  EINK_NO_MERGE = 2147483648,
};
struct disp_rectsz {
  unsigned int width;
  unsigned int height;
};
enum disp_pixel_format {
  DISP_FORMAT_ARGB_8888 = 0,
  DISP_FORMAT_ABGR_8888 = 1,
  DISP_FORMAT_RGBA_8888 = 2,
  DISP_FORMAT_BGRA_8888 = 3,
  DISP_FORMAT_XRGB_8888 = 4,
  DISP_FORMAT_XBGR_8888 = 5,
  DISP_FORMAT_RGBX_8888 = 6,
  DISP_FORMAT_BGRX_8888 = 7,
  DISP_FORMAT_RGB_888 = 8,
  DISP_FORMAT_BGR_888 = 9,
  DISP_FORMAT_RGB_565 = 10,
  DISP_FORMAT_BGR_565 = 11,
  DISP_FORMAT_ARGB_4444 = 12,
  DISP_FORMAT_ABGR_4444 = 13,
  DISP_FORMAT_RGBA_4444 = 14,
  DISP_FORMAT_BGRA_4444 = 15,
  DISP_FORMAT_ARGB_1555 = 16,
  DISP_FORMAT_ABGR_1555 = 17,
  DISP_FORMAT_RGBA_5551 = 18,
  DISP_FORMAT_BGRA_5551 = 19,
  DISP_FORMAT_A2R10G10B10 = 20,
  DISP_FORMAT_A2B10G10R10 = 21,
  DISP_FORMAT_R10G10B10A2 = 22,
  DISP_FORMAT_B10G10R10A2 = 23,
  DISP_FORMAT_YUV444_I_AYUV = 64,
  DISP_FORMAT_YUV444_I_VUYA = 65,
  DISP_FORMAT_YUV422_I_YVYU = 66,
  DISP_FORMAT_YUV422_I_YUYV = 67,
  DISP_FORMAT_YUV422_I_UYVY = 68,
  DISP_FORMAT_YUV422_I_VYUY = 69,
  DISP_FORMAT_YUV444_P = 70,
  DISP_FORMAT_YUV422_P = 71,
  DISP_FORMAT_YUV420_P = 72,
  DISP_FORMAT_YUV411_P = 73,
  DISP_FORMAT_YUV422_SP_UVUV = 74,
  DISP_FORMAT_YUV422_SP_VUVU = 75,
  DISP_FORMAT_YUV420_SP_UVUV = 76,
  DISP_FORMAT_YUV420_SP_VUVU = 77,
  DISP_FORMAT_YUV411_SP_UVUV = 78,
  DISP_FORMAT_YUV411_SP_VUVU = 79,
  DISP_FORMAT_8BIT_GRAY = 80,
  DISP_FORMAT_YUV444_I_AYUV_10BIT = 81,
  DISP_FORMAT_YUV444_I_VUYA_10BIT = 82,
  DISP_FORMAT_YUV422_I_YVYU_10BIT = 83,
  DISP_FORMAT_YUV422_I_YUYV_10BIT = 84,
  DISP_FORMAT_YUV422_I_UYVY_10BIT = 85,
  DISP_FORMAT_YUV422_I_VYUY_10BIT = 86,
  DISP_FORMAT_YUV444_P_10BIT = 87,
  DISP_FORMAT_YUV422_P_10BIT = 88,
  DISP_FORMAT_YUV420_P_10BIT = 89,
  DISP_FORMAT_YUV411_P_10BIT = 90,
  DISP_FORMAT_YUV422_SP_UVUV_10BIT = 91,
  DISP_FORMAT_YUV422_SP_VUVU_10BIT = 92,
  DISP_FORMAT_YUV420_SP_UVUV_10BIT = 93,
  DISP_FORMAT_YUV420_SP_VUVU_10BIT = 94,
  DISP_FORMAT_YUV411_SP_UVUV_10BIT = 95,
  DISP_FORMAT_YUV411_SP_VUVU_10BIT = 96,
  DISP_FORMAT_MAX = 97,
};
enum disp_color_space {
  DISP_UNDEF = 0,
  DISP_UNDEF_F = 1,
  DISP_GBR = 256,
  DISP_BT709 = 257,
  DISP_FCC = 258,
  DISP_BT470BG = 259,
  DISP_BT601 = 260,
  DISP_SMPTE240M = 261,
  DISP_YCGCO = 262,
  DISP_BT2020NC = 263,
  DISP_BT2020C = 264,
  DISP_GBR_F = 512,
  DISP_BT709_F = 513,
  DISP_FCC_F = 514,
  DISP_BT470BG_F = 515,
  DISP_BT601_F = 516,
  DISP_SMPTE240M_F = 517,
  DISP_YCGCO_F = 518,
  DISP_BT2020NC_F = 519,
  DISP_BT2020C_F = 520,
  DISP_RESERVED = 768,
  DISP_RESERVED_F = 769,
};
struct disp_rect64 {
  long long int x;
  long long int y;
  long long int width;
  long long int height;
};
enum disp_buffer_flags {
  DISP_BF_NORMAL = 0,
  DISP_BF_STEREO_TB = 1,
  DISP_BF_STEREO_FP = 2,
  DISP_BF_STEREO_SSH = 4,
  DISP_BF_STEREO_SSF = 8,
  DISP_BF_STEREO_LI = 16,
  DISP_BF_STEREO_2D_DEPTH = 32,
};
enum disp_scan_flags {
  DISP_SCAN_PROGRESSIVE = 0,
  DISP_SCAN_INTERLACED_ODD_FLD_FIRST = 1,
  DISP_SCAN_INTERLACED_EVEN_FLD_FIRST = 2,
};
enum disp_layer_mode {
  LAYER_MODE_BUFFER = 0,
  LAYER_MODE_COLOR = 1,
};
struct disp_rect {
  int x;
  int y;
  unsigned int width;
  unsigned int height;
};
enum disp_3d_out_mode {
  DISP_3D_OUT_MODE_CI_1 = 5,
  DISP_3D_OUT_MODE_CI_2 = 6,
  DISP_3D_OUT_MODE_CI_3 = 7,
  DISP_3D_OUT_MODE_CI_4 = 8,
  DISP_3D_OUT_MODE_LIRGB = 9,
  DISP_3D_OUT_MODE_TB = 0,
  DISP_3D_OUT_MODE_FP = 1,
  DISP_3D_OUT_MODE_SSF = 2,
  DISP_3D_OUT_MODE_SSH = 3,
  DISP_3D_OUT_MODE_LI = 4,
  DISP_3D_OUT_MODE_FA = 10,
};
enum disp_eotf {
  DISP_EOTF_RESERVED = 0,
  DISP_EOTF_BT709 = 1,
  DISP_EOTF_UNDEF = 2,
  DISP_EOTF_GAMMA22 = 4,
  DISP_EOTF_GAMMA28 = 5,
  DISP_EOTF_BT601 = 6,
  DISP_EOTF_SMPTE240M = 7,
  DISP_EOTF_LINEAR = 8,
  DISP_EOTF_LOG100 = 9,
  DISP_EOTF_LOG100S10 = 10,
  DISP_EOTF_IEC61966_2_4 = 11,
  DISP_EOTF_BT1361 = 12,
  DISP_EOTF_IEC61966_2_1 = 13,
  DISP_EOTF_BT2020_0 = 14,
  DISP_EOTF_BT2020_1 = 15,
  DISP_EOTF_SMPTE2084 = 16,
  DISP_EOTF_SMPTE428_1 = 17,
  DISP_EOTF_ARIB_STD_B67 = 18,
};
enum disp_atw_mode {
  NORMAL_MODE = 0,
  LEFT_RIGHT_MODE = 1,
  UP_DOWN_MODE = 2,
};
struct disp_atw_info {
  bool used;
  enum disp_atw_mode mode;
  unsigned int b_row;
  unsigned int b_col;
  int cof_fd;
};
struct disp_fb_info2 {
  int fd;
  int y8_fd;
  struct disp_rectsz size[3];
  unsigned int align[3];
  enum disp_pixel_format format;
  enum disp_color_space color_space;
  int trd_right_fd;
  bool pre_multiply;
  struct disp_rect64 crop;
  enum disp_buffer_flags flags;
  enum disp_scan_flags scan;
  enum disp_eotf eotf;
  int depth;
  unsigned int fbd_en;
  int metadata_fd;
  unsigned int metadata_size;
  unsigned int metadata_flag;
};
struct disp_layer_info2 {
  enum disp_layer_mode mode;
  unsigned char zorder;
  unsigned char alpha_mode;
  unsigned char alpha_value;
  struct disp_rect screen_win;
  bool b_trd_out;
  enum disp_3d_out_mode out_trd_mode;
  union {
    unsigned int color;
    struct disp_fb_info2 fb;
  };
  unsigned int id;
  struct disp_atw_info atw;
};
struct disp_layer_config2 {
  struct disp_layer_info2 info;
  bool enable;
  unsigned int channel;
  unsigned int layer_id;
};
static const int DISP_EINK_UPDATE2 = 1030;
static const int DISP_EINK_WAIT_BEFORE_LCD_INT_COMPLETE = 16402;
static const int DISP_EINK_SET_UPDATE_CONTROL = 16403;
static const int DISP_EINK_WAIT_FRAME_SYNC_COMPLETE = 16404;
static const int DISP_EINK_SET_NTX_HANDWRITE_ONOFF = 16405;
static const int DISP_EINK_SET_WAIT_MODE_ONOFF = 16406;
typedef struct {
  long unsigned int u0;
  long unsigned int u1;
  long unsigned int u2;
  long unsigned int u3;
  long unsigned int u4;
  long unsigned int u5;
  long unsigned int u6;
} sunxi_disp_raw_ioctl;
typedef struct {
  struct area_info *area;
  long unsigned int layer_num;
  long unsigned int update_mode;
  struct disp_layer_config2 *lyr_cfg2;
  unsigned int *frame_id;
  uint32_t *rotate;
  long unsigned int cfa_use;
} sunxi_disp_eink_update2;
typedef struct {
  bool enable;
} sunxi_disp_eink_set_update_control;
typedef struct {
  uint32_t frame_id;
} sunxi_disp_eink_wait_frame_sync_complete;
typedef struct {
  bool enable;
} sunxi_disp_eink_set_ntx_handwrite_onoff;
typedef struct {
  bool enable;
} sunxi_disp_eink_set_wait_mode_onoff;
struct disp_fb_info {
  long long unsigned int addr[3];
  struct disp_rectsz size[3];
  unsigned int align[3];
  enum disp_pixel_format format;
  enum disp_color_space color_space;
  unsigned int trd_right_addr[3];
  bool pre_multiply;
  struct disp_rect64 crop;
  enum disp_buffer_flags flags;
  enum disp_scan_flags scan;
};
struct disp_layer_info {
  enum disp_layer_mode mode;
  unsigned char zorder;
  unsigned char alpha_mode;
  unsigned char alpha_value;
  struct disp_rect screen_win;
  bool b_trd_out;
  enum disp_3d_out_mode out_trd_mode;
  union {
    unsigned int color;
    struct disp_fb_info fb;
  };
  unsigned int id;
};
struct disp_layer_config {
  struct disp_layer_info info;
  bool enable;
  unsigned int channel;
  unsigned int layer_id;
};
typedef struct {
  struct area_info *area;
  long unsigned int layer_num;
  long unsigned int update_mode;
  struct disp_layer_config *lyr_cfg;
  long unsigned int u4;
  long unsigned int rotate;
  long unsigned int cfa_use;
} sunxi_disp_eink_update;
typedef struct {
  long unsigned int temp;
} sunxi_disp_eink_set_temp;
typedef struct {
  long unsigned int skip;
} sunxi_disp_eink_overlap_skip;
typedef struct {
  long unsigned int count;
} sunxi_disp_eink_set_gc_count;
struct cfa_enable {
  bool bg_enable;
  int is_cfa;
};
typedef struct {
  struct cfa_enable cfa;
} sunxi_disp_eink_set_bg_onoff;
typedef struct {
  int screen_id;
  struct disp_layer_config2 *lyr_cfg2;
  long unsigned int layer_num;
} sunxi_disp_layer_get_config2;
typedef struct {
  int screen_id;
  struct disp_layer_config *lyr_cfg;
  long unsigned int layer_num;
} sunxi_disp_layer_get_config;
typedef struct {
  int screen_id;
} sunxi_disp_layer_generic_get;
typedef union {
  sunxi_disp_raw_ioctl raw;
  sunxi_disp_eink_update update;
  sunxi_disp_eink_update2 update2;
  sunxi_disp_eink_set_temp set_temp;
  sunxi_disp_eink_overlap_skip op_skip;
  sunxi_disp_eink_set_gc_count gc_cnt;
  sunxi_disp_eink_set_bg_onoff toggle_bg;
  sunxi_disp_eink_set_update_control upd_ctrl;
  sunxi_disp_eink_wait_frame_sync_complete wait_for;
  sunxi_disp_eink_set_ntx_handwrite_onoff toggle_handw;
  sunxi_disp_eink_set_wait_mode_onoff toggle_wait;
  sunxi_disp_layer_get_config get_layer;
  sunxi_disp_layer_get_config2 get_layer2;
  sunxi_disp_layer_generic_get get;
} sunxi_disp_eink_ioctl;
]]
