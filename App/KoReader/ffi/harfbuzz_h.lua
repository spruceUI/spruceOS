local ffi = require("ffi")

ffi.cdef[[
typedef uint32_t hb_codepoint_t;
union _hb_var_int_t {
  uint32_t u32;
  int32_t i32;
  uint16_t u16[2];
  int16_t i16[2];
  uint8_t u8[4];
  int8_t i8[4];
};
typedef union _hb_var_int_t hb_var_int_t;
typedef struct hb_face_t hb_face_t;
typedef const struct hb_language_impl_t *hb_language_t;
typedef unsigned int hb_ot_name_id_t;
struct hb_ot_name_entry_t {
  hb_ot_name_id_t name_id;
  hb_var_int_t var;
  hb_language_t language;
};
typedef struct hb_ot_name_entry_t hb_ot_name_entry_t;
typedef struct hb_set_t hb_set_t;
const hb_ot_name_entry_t *hb_ot_name_list_names(hb_face_t *, unsigned int *);
const char *hb_language_to_string(hb_language_t);
unsigned int hb_ot_name_get_utf8(hb_face_t *, hb_ot_name_id_t, hb_language_t, unsigned int *, char *);
hb_set_t *hb_set_create(void);
void hb_face_collect_unicodes(hb_face_t *, hb_set_t *);
void hb_set_set(hb_set_t *, const hb_set_t *);
void hb_set_intersect(hb_set_t *, const hb_set_t *);
unsigned int hb_set_get_population(const hb_set_t *);
void hb_set_destroy(hb_set_t *);
void hb_face_destroy(hb_face_t *);
void hb_set_add_range(hb_set_t *, hb_codepoint_t, hb_codepoint_t);
typedef struct hb_blob_t hb_blob_t;
typedef enum {
  HB_MEMORY_MODE_DUPLICATE = 0,
  HB_MEMORY_MODE_READONLY = 1,
  HB_MEMORY_MODE_WRITABLE = 2,
  HB_MEMORY_MODE_READONLY_MAY_MAKE_WRITABLE = 3,
} hb_memory_mode_t;
typedef void (*hb_destroy_func_t)(void *);
static const int HB_OT_NAME_ID_FONT_FAMILY = 1;
static const int HB_OT_NAME_ID_FONT_SUBFAMILY = 2;
static const int HB_OT_NAME_ID_FULL_NAME = 4;
typedef struct FT_FaceRec_ *FT_Face;
hb_blob_t *hb_blob_create(const char *, unsigned int, hb_memory_mode_t, void *, hb_destroy_func_t);
hb_face_t *hb_face_create(hb_blob_t *, unsigned int);
void hb_blob_destroy(hb_blob_t *);
unsigned int hb_face_get_glyph_count(const hb_face_t *);
hb_face_t *hb_ft_face_create_referenced(FT_Face);
]]
