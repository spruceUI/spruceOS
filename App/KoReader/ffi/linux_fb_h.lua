local ffi = require("ffi")

ffi.cdef[[
static const int FBIOGET_FSCREENINFO = 17922;
static const int FBIOGET_VSCREENINFO = 17920;
static const int FBIOPUT_VSCREENINFO = 17921;
static const int FB_TYPE_PACKED_PIXELS = 0;
static const int FB_ROTATE_UR = 0;
static const int FB_ROTATE_CW = 1;
static const int FB_ROTATE_UD = 2;
static const int FB_ROTATE_CCW = 3;
struct fb_bitfield {
  unsigned int offset;
  unsigned int length;
  unsigned int msb_right;
};
struct fb_fix_screeninfo {
  char id[16];
  long unsigned int smem_start;
  unsigned int smem_len;
  unsigned int type;
  unsigned int type_aux;
  unsigned int visual;
  short unsigned int xpanstep;
  short unsigned int ypanstep;
  short unsigned int ywrapstep;
  unsigned int line_length;
  long unsigned int mmio_start;
  unsigned int mmio_len;
  unsigned int accel;
  short unsigned int capabilities;
  short unsigned int reserved[2];
};
struct fb_var_screeninfo {
  unsigned int xres;
  unsigned int yres;
  unsigned int xres_virtual;
  unsigned int yres_virtual;
  unsigned int xoffset;
  unsigned int yoffset;
  unsigned int bits_per_pixel;
  unsigned int grayscale;
  struct fb_bitfield red;
  struct fb_bitfield green;
  struct fb_bitfield blue;
  struct fb_bitfield transp;
  unsigned int nonstd;
  unsigned int activate;
  unsigned int height;
  unsigned int width;
  unsigned int accel_flags;
  unsigned int pixclock;
  unsigned int left_margin;
  unsigned int right_margin;
  unsigned int upper_margin;
  unsigned int lower_margin;
  unsigned int hsync_len;
  unsigned int vsync_len;
  unsigned int sync;
  unsigned int vmode;
  unsigned int rotate;
  unsigned int colorspace;
  unsigned int reserved[4];
};
]]
