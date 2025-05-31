local ffi = require("ffi")

ffi.cdef[[
enum fx_type {
  fx_mask = 11,
  fx_buf_is_mask = 14,
  fx_none = -1,
  fx_flash = 20,
  fx_invert = 21,
  fx_update_partial = 0,
  fx_update_full = 1,
  fx_update_fast = 2,
  fx_update_slow = 3,
  fx_buffer_load = 99,
  fx_buffer_display_partial = 100,
  fx_buffer_display_full = 101,
};
struct update_area_t {
  int x1;
  int y1;
  int x2;
  int y2;
  enum fx_type which_fx;
  unsigned char *buffer;
};
enum orientation_t {
  orientation_portrait = 0,
  orientation_portrait_upside_down = 1,
  orientation_landscape = 2,
  orientation_landscape_upside_down = 3,
};
enum einkfb_events_t {
  einkfb_event_update_display = 0,
  einkfb_event_update_display_area = 1,
  einkfb_event_blank_display = 2,
  einkfb_event_rotate_display = 3,
  einkfb_event_null = -1,
};
struct einkfb_event_t {
  enum einkfb_events_t event;
  enum fx_type update_mode;
  int x1;
  int y1;
  int x2;
  int y2;
  enum orientation_t orientation;
};
static const int FBIO_EINK_UPDATE_DISPLAY = 18139;
static const int FBIO_EINK_UPDATE_DISPLAY_AREA = 18141;
static const int FBIO_EINK_SET_DISPLAY_ORIENTATION = 18160;
static const int FBIO_EINK_GET_DISPLAY_ORIENTATION = 18161;
]]
