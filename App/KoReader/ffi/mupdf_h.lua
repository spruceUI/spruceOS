local ffi = require("ffi")

ffi.cdef[[
static const int FZ_STEXT_BLOCK_TEXT = 0;
typedef struct fz_point_s fz_point;
struct fz_point_s {
  float x;
  float y;
};
typedef struct fz_rect_s fz_rect;
struct fz_rect_s {
  float x0;
  float y0;
  float x1;
  float y1;
};
extern const fz_rect fz_unit_rect;
extern const fz_rect fz_empty_rect;
extern const fz_rect fz_infinite_rect;
fz_rect *fz_intersect_rect(fz_rect *restrict, const fz_rect *restrict);
fz_rect *fz_union_rect(fz_rect *restrict, const fz_rect *restrict);
typedef struct fz_irect_s fz_irect;
struct fz_irect_s {
  int x0;
  int y0;
  int x1;
  int y1;
};
extern const fz_irect fz_empty_irect;
extern const fz_irect fz_infinite_irect;
fz_irect *fz_intersect_irect(fz_irect *restrict, const fz_irect *restrict);
fz_irect *fz_irect_from_rect(fz_irect *restrict, const fz_rect *restrict);
fz_irect *fz_round_rect(fz_irect *restrict, const fz_rect *restrict);
typedef struct fz_matrix_s fz_matrix;
struct fz_matrix_s {
  float a;
  float b;
  float c;
  float d;
  float e;
  float f;
};
extern const fz_matrix fz_identity;
fz_matrix *fz_concat(fz_matrix *, const fz_matrix *, const fz_matrix *);
fz_matrix *fz_scale(fz_matrix *, float, float);
fz_matrix *fz_pre_scale(fz_matrix *, float, float);
fz_matrix *fz_rotate(fz_matrix *, float);
fz_matrix *fz_pre_rotate(fz_matrix *, float);
fz_matrix *fz_translate(fz_matrix *, float, float);
fz_matrix *fz_pre_translate(fz_matrix *, float, float);
fz_rect *fz_transform_rect(fz_rect *restrict, const fz_matrix *restrict);
typedef struct fz_context_s fz_context;
typedef struct fz_font_s fz_font;
typedef struct fz_hash_table_s fz_hash_table;
typedef struct fz_storable_s fz_storable;
typedef struct fz_key_storable_s fz_key_storable;
typedef void fz_store_drop_fn(fz_context *, fz_storable *);
struct fz_storable_s {
  int refs;
  fz_store_drop_fn *drop;
};
struct fz_key_storable_s {
  fz_storable storable;
  short int store_key_refs;
};
void fz_install_external_font_funcs(fz_context *);
struct fz_buffer_s *mupdf_new_buffer_from_shared_data(fz_context *, const unsigned char *, size_t);
void *mupdf_drop_buffer(fz_context *, struct fz_buffer_s *);
typedef struct fz_alloc_context_s fz_alloc_context;
typedef struct fz_colorspace_s fz_colorspace;
fz_context *fz_new_context_imp(const fz_alloc_context *, const struct fz_locks_context_s *, size_t, const char *);
void fz_drop_context(fz_context *);
void fz_register_document_handlers(fz_context *);
typedef struct fz_image_s fz_image;
typedef struct fz_pixmap_s fz_pixmap;
struct fz_image_s {
  fz_key_storable key_storable;
  int w;
  int h;
  uint8_t n;
  uint8_t bpc;
  unsigned int imagemask : 1;
  unsigned int interpolate : 1;
  unsigned int use_colorkey : 1;
  unsigned int use_decode : 1;
  unsigned int invert_cmyk_jpeg : 1;
  unsigned int decoded : 1;
  unsigned int scalable : 1;
  fz_image *mask;
  int xres;
  int yres;
  fz_colorspace *colorspace;
  void (*drop_image)(fz_context *, fz_image *);
  fz_pixmap *(*get_pixmap)(fz_context *, fz_image *, fz_irect *, int, int, int *);
  size_t (*get_size)(fz_context *, fz_image *);
  int colorkey[64];
  float decode[64];
};
struct fz_pixmap_s {
  fz_storable storable;
  int x;
  int y;
  int w;
  int h;
  unsigned char n;
  unsigned char s;
  unsigned char alpha;
  unsigned char flags;
  ptrdiff_t stride;
  struct fz_separations_s *seps;
  int xres;
  int yres;
  fz_colorspace *colorspace;
  unsigned char *samples;
  fz_pixmap *underlying;
};
fz_image *mupdf_new_image_from_buffer(fz_context *, struct fz_buffer_s *);
fz_pixmap *mupdf_get_pixmap_from_image(fz_context *, fz_image *, const fz_irect *, fz_matrix *, int *, int *);
void *mupdf_save_pixmap_as_png(fz_context *, fz_pixmap *, const char *);
fz_image *fz_keep_image(fz_context *, fz_image *);
void fz_drop_image(fz_context *, fz_image *);
fz_pixmap *fz_load_png(fz_context *, const unsigned char *, size_t);
int fz_runetochar(char *, int);
typedef struct fz_annot_s fz_annot;
struct fz_annot_s {
  int refs;
  void (*drop_annot)(fz_context *, fz_annot *);
  fz_rect *(*bound_annot)(fz_context *, fz_annot *, fz_rect *);
  void (*run_annot)(fz_context *, fz_annot *, struct fz_device_s *, const fz_matrix *, struct fz_cookie_s *);
  fz_annot *(*next_annot)(fz_context *, fz_annot *);
};
typedef struct fz_outline_s fz_outline;
struct fz_outline_s {
  int refs;
  char *title;
  char *uri;
  int page;
  float x;
  float y;
  fz_outline *next;
  fz_outline *down;
  int is_open;
};
typedef struct fz_document_s fz_document;
typedef struct fz_page_s fz_page;
typedef struct fz_link_s fz_link;
struct fz_document_s {
  int refs;
  void (*drop_document)(fz_context *, fz_document *);
  int (*needs_password)(fz_context *, fz_document *);
  int (*authenticate_password)(fz_context *, fz_document *, const char *);
  int (*has_permission)(fz_context *, fz_document *, enum {
    FZ_PERMISSION_PRINT = 112,
    FZ_PERMISSION_COPY = 99,
    FZ_PERMISSION_EDIT = 101,
    FZ_PERMISSION_ANNOTATE = 110,
  });
  fz_outline *(*load_outline)(fz_context *, fz_document *);
  void (*layout)(fz_context *, fz_document *, float, float, float);
  intptr_t (*make_bookmark)(fz_context *, fz_document *, int);
  int (*lookup_bookmark)(fz_context *, fz_document *, intptr_t);
  int (*resolve_link)(fz_context *, fz_document *, const char *, float *, float *);
  int (*count_pages)(fz_context *, fz_document *);
  fz_page *(*load_page)(fz_context *, fz_document *, int);
  int (*lookup_metadata)(fz_context *, fz_document *, const char *, char *, int);
  fz_colorspace *(*get_output_intent)(fz_context *, fz_document *);
  int did_layout;
  int is_reflowable;
};
struct fz_page_s {
  int refs;
  void (*drop_page)(fz_context *, fz_page *);
  fz_rect *(*bound_page)(fz_context *, fz_page *, fz_rect *);
  void (*run_page_contents)(fz_context *, fz_page *, struct fz_device_s *, const fz_matrix *, struct fz_cookie_s *);
  fz_link *(*load_links)(fz_context *, fz_page *);
  fz_annot *(*first_annot)(fz_context *, fz_page *);
  struct fz_transition_s *(*page_presentation)(fz_context *, fz_page *, struct fz_transition_s *, float *);
  void (*control_separation)(fz_context *, fz_page *, int, int);
  int (*separation_disabled)(fz_context *, fz_page *, int);
  struct fz_separations_s *(*separations)(fz_context *, fz_page *);
  int (*overprint)(fz_context *, fz_page *);
};
fz_document *mupdf_open_document(fz_context *, const char *);
fz_document *mupdf_open_document_with_stream(fz_context *, const char *, struct fz_stream_s *);
int fz_is_document_reflowable(fz_context *, fz_document *);
int fz_needs_password(fz_context *, fz_document *);
int fz_authenticate_password(fz_context *, fz_document *, const char *);
void fz_drop_document(fz_context *, fz_document *);
int mupdf_count_pages(fz_context *, fz_document *);
void *mupdf_layout_document(fz_context *, fz_document *, float, float, float);
int fz_lookup_metadata(fz_context *, fz_document *, const char *, char *, int);
int fz_resolve_link(fz_context *, fz_document *, const char *, float *, float *);
fz_page *mupdf_load_page(fz_context *, fz_document *, int);
fz_rect *fz_bound_page(fz_context *, fz_page *, fz_rect *);
void fz_drop_page(fz_context *, fz_page *);
struct fz_link_s {
  int refs;
  fz_link *next;
  fz_rect rect;
  void *doc;
  char *uri;
};
fz_link *mupdf_load_links(fz_context *, fz_page *);
void fz_drop_link(fz_context *, fz_link *);
fz_outline *mupdf_load_outline(fz_context *, fz_document *);
void fz_drop_outline(fz_context *, fz_outline *);
void *mupdf_drop_stream(fz_context *, struct fz_stream_s *);
struct fz_stream_s *mupdf_open_memory(fz_context *, const unsigned char *, size_t);
typedef struct fz_stext_char_s fz_stext_char;
struct fz_stext_char_s {
  int c;
  fz_point origin;
  fz_rect bbox;
  float size;
  fz_font *font;
  fz_stext_char *next;
};
typedef struct fz_stext_line_s fz_stext_line;
struct fz_stext_line_s {
  int wmode;
  fz_point dir;
  fz_rect bbox;
  fz_stext_char *first_char;
  fz_stext_char *last_char;
  fz_stext_line *prev;
  fz_stext_line *next;
};
typedef struct fz_stext_block_s fz_stext_block;
struct fz_stext_block_s {
  int type;
  fz_rect bbox;
  union {
    struct {
      fz_stext_line *first_line;
      fz_stext_line *last_line;
    } t;
    struct {
      fz_matrix transform;
      fz_image *image;
    } i;
  } u;
  fz_stext_block *prev;
  fz_stext_block *next;
};
typedef struct fz_stext_options_s fz_stext_options;
struct fz_stext_options_s {
  int flags;
};
typedef struct fz_stext_page_s fz_stext_page;
struct fz_stext_page_s {
  struct fz_pool_s *pool;
  fz_rect mediabox;
  fz_stext_block *first_block;
  fz_stext_block *last_block;
};
fz_stext_page *mupdf_new_stext_page_from_page(fz_context *, fz_page *, const fz_stext_options *);
void fz_drop_stext_page(fz_context *, fz_stext_page *);
fz_pixmap *mupdf_new_pixmap(fz_context *, fz_colorspace *, int, int, struct fz_separations_s *, int);
fz_pixmap *fz_new_pixmap(fz_context *, fz_colorspace *, int, int, struct fz_separations_s *, int);
fz_pixmap *mupdf_new_pixmap_with_bbox(fz_context *, fz_colorspace *, const fz_irect *, struct fz_separations_s *, int);
fz_pixmap *mupdf_new_pixmap_with_data(fz_context *, fz_colorspace *, int, int, struct fz_separations_s *, int, int, unsigned char *);
fz_pixmap *mupdf_new_pixmap_with_bbox_and_data(fz_context *, fz_colorspace *, const fz_irect *, struct fz_separations_s *, int, unsigned char *);
fz_pixmap *fz_convert_pixmap(fz_context *, fz_pixmap *, fz_colorspace *, fz_colorspace *, struct fz_default_colorspaces_s *, const struct fz_color_params_s *, int);
fz_pixmap *fz_keep_pixmap(fz_context *, fz_pixmap *);
void fz_drop_pixmap(fz_context *, fz_pixmap *);
void fz_clear_pixmap_with_value(fz_context *, fz_pixmap *, int);
void fz_gamma_pixmap(fz_context *, fz_pixmap *, float);
fz_pixmap *fz_scale_pixmap(fz_context *, fz_pixmap *, float, float, float, float, fz_irect *);
int fz_pixmap_width(fz_context *, fz_pixmap *);
int fz_pixmap_height(fz_context *, fz_pixmap *);
int fz_pixmap_components(fz_context *, fz_pixmap *);
unsigned char *fz_pixmap_samples(fz_context *, fz_pixmap *);
fz_colorspace *fz_device_gray(fz_context *);
fz_colorspace *fz_device_rgb(fz_context *);
fz_colorspace *fz_device_bgr(fz_context *);
struct fz_color_params_s {
  uint8_t ri;
  uint8_t bp;
  uint8_t op;
  uint8_t opm;
};
const struct fz_color_params_s *fz_default_color_params(fz_context *);
struct fz_device_s *mupdf_new_draw_device(fz_context *, const fz_matrix *, fz_pixmap *);
struct fz_device_s *mupdf_new_text_device(fz_context *, fz_stext_page *, const fz_stext_options *);
struct fz_device_s *mupdf_new_bbox_device(fz_context *, fz_rect *);
void *mupdf_run_page(fz_context *, fz_page *, struct fz_device_s *, const fz_matrix *, struct fz_cookie_s *);
void fz_close_device(fz_context *, struct fz_device_s *);
void fz_drop_device(fz_context *, struct fz_device_s *);
enum pdf_annot_type {
  PDF_ANNOT_TEXT = 0,
  PDF_ANNOT_LINK = 1,
  PDF_ANNOT_FREE_TEXT = 2,
  PDF_ANNOT_LINE = 3,
  PDF_ANNOT_SQUARE = 4,
  PDF_ANNOT_CIRCLE = 5,
  PDF_ANNOT_POLYGON = 6,
  PDF_ANNOT_POLY_LINE = 7,
  PDF_ANNOT_HIGHLIGHT = 8,
  PDF_ANNOT_UNDERLINE = 9,
  PDF_ANNOT_SQUIGGLY = 10,
  PDF_ANNOT_STRIKE_OUT = 11,
  PDF_ANNOT_STAMP = 12,
  PDF_ANNOT_CARET = 13,
  PDF_ANNOT_INK = 14,
  PDF_ANNOT_POPUP = 15,
  PDF_ANNOT_FILE_ATTACHMENT = 16,
  PDF_ANNOT_SOUND = 17,
  PDF_ANNOT_MOVIE = 18,
  PDF_ANNOT_WIDGET = 19,
  PDF_ANNOT_SCREEN = 20,
  PDF_ANNOT_PRINTER_MARK = 21,
  PDF_ANNOT_TRAP_NET = 22,
  PDF_ANNOT_WATERMARK = 23,
  PDF_ANNOT_3D = 24,
  PDF_ANNOT_UNKNOWN = -1,
};
typedef struct pdf_hotspot_s pdf_hotspot;
struct pdf_hotspot_s {
  int num;
  int state;
};
typedef struct pdf_lexbuf_s pdf_lexbuf;
struct pdf_lexbuf_s {
  int size;
  int base_size;
  int len;
  int64_t i;
  float f;
  char *scratch;
  char buffer[256];
};
typedef struct pdf_lexbuf_large_s pdf_lexbuf_large;
struct pdf_lexbuf_large_s {
  pdf_lexbuf base;
  char buffer[65280];
};
typedef struct pdf_obj_s pdf_obj;
typedef struct pdf_annot_s pdf_annot;
typedef struct pdf_page_s pdf_page;
struct pdf_annot_s {
  fz_annot super;
  pdf_page *page;
  pdf_obj *obj;
  pdf_obj *ap;
  int needs_new_ap;
  int has_new_ap;
  pdf_annot *next;
};
typedef struct pdf_document_s pdf_document;
struct pdf_document_s {
  fz_document super;
  struct fz_stream_s *file;
  int version;
  int64_t startxref;
  int64_t file_size;
  struct pdf_crypt_s *crypt;
  struct pdf_ocg_descriptor_s *ocg;
  struct pdf_portfolio_s *portfolio;
  pdf_hotspot hotspot;
  fz_colorspace *oi;
  int max_xref_len;
  int num_xref_sections;
  int saved_num_xref_sections;
  int num_incremental_sections;
  int xref_base;
  int disallow_new_increments;
  struct pdf_xref_s *xref_sections;
  struct pdf_xref_s *saved_xref_sections;
  int *xref_index;
  int freeze_updates;
  int has_xref_streams;
  int rev_page_count;
  struct pdf_rev_page_map_s *rev_page_map;
  int repair_attempted;
  int file_reading_linearly;
  int64_t file_length;
  int linear_page_count;
  pdf_obj *linear_obj;
  pdf_obj **linear_page_refs;
  int linear_page1_obj_num;
  int64_t linear_pos;
  int linear_page_num;
  int hint_object_offset;
  int hint_object_length;
  int hints_loaded;
  struct {
    int number;
    int64_t offset;
    int64_t index;
  } *hint_page;
  int *hint_shared_ref;
  struct {
    int number;
    int64_t offset;
  } *hint_shared;
  int hint_obj_offsets_max;
  int64_t *hint_obj_offsets;
  int resources_localised;
  pdf_lexbuf_large lexbuf;
  pdf_annot *focus;
  pdf_obj *focus_obj;
  struct pdf_js_s *js;
  int recalculating;
  int dirty;
  void (*event_cb)(fz_context *, pdf_document *, struct pdf_doc_event_s *, void *);
  void *event_cb_data;
  int num_type3_fonts;
  int max_type3_fonts;
  fz_font **type3_fonts;
  struct {
    fz_hash_table *images;
    fz_hash_table *fonts;
  } resources;
  int orphans_max;
  int orphans_count;
  pdf_obj **orphans;
};
pdf_document *pdf_specifics(fz_context *, fz_document *);
pdf_annot *mupdf_pdf_create_annot(fz_context *, pdf_page *, enum pdf_annot_type);
void *mupdf_pdf_delete_annot(fz_context *, pdf_page *, pdf_annot *);
void *mupdf_pdf_set_annot_quad_points(fz_context *, pdf_annot *, int, const float *);
void *mupdf_pdf_set_annot_contents(fz_context *, pdf_annot *, const char *);
pdf_annot *mupdf_pdf_first_annot(fz_context *, pdf_page *);
pdf_annot *mupdf_pdf_next_annot(fz_context *, pdf_annot *);
int mupdf_pdf_annot_quad_point_count(fz_context *, pdf_annot *);
void *mupdf_pdf_annot_quad_point(fz_context *, pdf_annot *, int, float *);
void *mupdf_pdf_set_text_annot_position(fz_context *, pdf_annot *, fz_point);
void *mupdf_pdf_set_markup_appearance(fz_context *, pdf_document *, pdf_annot *, float *, float, float, float);
typedef struct pdf_write_options_s pdf_write_options;
struct pdf_write_options_s {
  int do_incremental;
  int do_pretty;
  int do_ascii;
  int do_compress;
  int do_compress_images;
  int do_compress_fonts;
  int do_decompress;
  int do_garbage;
  int do_linear;
  int do_clean;
  int do_sanitize;
  int continue_on_error;
  int *errors;
};
void *mupdf_pdf_save_document(fz_context *, pdf_document *, const char *, pdf_write_options *);
fz_alloc_context *mupdf_get_my_alloc_context();
int mupdf_get_cache_size();
int mupdf_error_code(fz_context *);
char *mupdf_error_message(fz_context *);
]]
