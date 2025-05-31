local ffi = require("ffi")

ffi.cdef[[
typedef int8_t utf8proc_int8_t;
typedef uint8_t utf8proc_uint8_t;
typedef int16_t utf8proc_int16_t;
typedef uint16_t utf8proc_uint16_t;
typedef int32_t utf8proc_int32_t;
typedef uint32_t utf8proc_uint32_t;
typedef ssize_t utf8proc_ssize_t;
typedef size_t utf8proc_size_t;
typedef bool utf8proc_bool;
typedef enum {
  UTF8PROC_NULLTERM = 1,
  UTF8PROC_STABLE = 2,
  UTF8PROC_COMPAT = 4,
  UTF8PROC_COMPOSE = 8,
  UTF8PROC_DECOMPOSE = 16,
  UTF8PROC_IGNORE = 32,
  UTF8PROC_REJECTNA = 64,
  UTF8PROC_NLF2LS = 128,
  UTF8PROC_NLF2PS = 256,
  UTF8PROC_NLF2LF = 384,
  UTF8PROC_STRIPCC = 512,
  UTF8PROC_CASEFOLD = 1024,
  UTF8PROC_CHARBOUND = 2048,
  UTF8PROC_LUMP = 4096,
  UTF8PROC_STRIPMARK = 8192,
  UTF8PROC_STRIPNA = 16384,
} utf8proc_option_t;
static const int UTF8PROC_ERROR_NOMEM = -1;
static const int UTF8PROC_ERROR_OVERFLOW = -2;
static const int UTF8PROC_ERROR_INVALIDUTF8 = -3;
static const int UTF8PROC_ERROR_NOTASSIGNED = -4;
static const int UTF8PROC_ERROR_INVALIDOPTS = -5;
typedef short int utf8proc_propval_t;
struct utf8proc_property_struct {
  utf8proc_propval_t category;
  utf8proc_propval_t combining_class;
  utf8proc_propval_t bidi_class;
  utf8proc_propval_t decomp_type;
  utf8proc_uint16_t decomp_seqindex;
  utf8proc_uint16_t casefold_seqindex;
  utf8proc_uint16_t uppercase_seqindex;
  utf8proc_uint16_t lowercase_seqindex;
  utf8proc_uint16_t titlecase_seqindex;
  utf8proc_uint16_t comb_index;
  unsigned int bidi_mirrored : 1;
  unsigned int comp_exclusion : 1;
  unsigned int ignorable : 1;
  unsigned int control_boundary : 1;
  unsigned int charwidth : 2;
  unsigned int pad : 2;
  unsigned int boundclass : 6;
  unsigned int indic_conjunct_break : 2;
};
typedef struct utf8proc_property_struct utf8proc_property_t;
typedef enum {
  UTF8PROC_CATEGORY_CN = 0,
  UTF8PROC_CATEGORY_LU = 1,
  UTF8PROC_CATEGORY_LL = 2,
  UTF8PROC_CATEGORY_LT = 3,
  UTF8PROC_CATEGORY_LM = 4,
  UTF8PROC_CATEGORY_LO = 5,
  UTF8PROC_CATEGORY_MN = 6,
  UTF8PROC_CATEGORY_MC = 7,
  UTF8PROC_CATEGORY_ME = 8,
  UTF8PROC_CATEGORY_ND = 9,
  UTF8PROC_CATEGORY_NL = 10,
  UTF8PROC_CATEGORY_NO = 11,
  UTF8PROC_CATEGORY_PC = 12,
  UTF8PROC_CATEGORY_PD = 13,
  UTF8PROC_CATEGORY_PS = 14,
  UTF8PROC_CATEGORY_PE = 15,
  UTF8PROC_CATEGORY_PI = 16,
  UTF8PROC_CATEGORY_PF = 17,
  UTF8PROC_CATEGORY_PO = 18,
  UTF8PROC_CATEGORY_SM = 19,
  UTF8PROC_CATEGORY_SC = 20,
  UTF8PROC_CATEGORY_SK = 21,
  UTF8PROC_CATEGORY_SO = 22,
  UTF8PROC_CATEGORY_ZS = 23,
  UTF8PROC_CATEGORY_ZL = 24,
  UTF8PROC_CATEGORY_ZP = 25,
  UTF8PROC_CATEGORY_CC = 26,
  UTF8PROC_CATEGORY_CF = 27,
  UTF8PROC_CATEGORY_CS = 28,
  UTF8PROC_CATEGORY_CO = 29,
} utf8proc_category_t;
typedef enum {
  UTF8PROC_BIDI_CLASS_L = 1,
  UTF8PROC_BIDI_CLASS_LRE = 2,
  UTF8PROC_BIDI_CLASS_LRO = 3,
  UTF8PROC_BIDI_CLASS_R = 4,
  UTF8PROC_BIDI_CLASS_AL = 5,
  UTF8PROC_BIDI_CLASS_RLE = 6,
  UTF8PROC_BIDI_CLASS_RLO = 7,
  UTF8PROC_BIDI_CLASS_PDF = 8,
  UTF8PROC_BIDI_CLASS_EN = 9,
  UTF8PROC_BIDI_CLASS_ES = 10,
  UTF8PROC_BIDI_CLASS_ET = 11,
  UTF8PROC_BIDI_CLASS_AN = 12,
  UTF8PROC_BIDI_CLASS_CS = 13,
  UTF8PROC_BIDI_CLASS_NSM = 14,
  UTF8PROC_BIDI_CLASS_BN = 15,
  UTF8PROC_BIDI_CLASS_B = 16,
  UTF8PROC_BIDI_CLASS_S = 17,
  UTF8PROC_BIDI_CLASS_WS = 18,
  UTF8PROC_BIDI_CLASS_ON = 19,
  UTF8PROC_BIDI_CLASS_LRI = 20,
  UTF8PROC_BIDI_CLASS_RLI = 21,
  UTF8PROC_BIDI_CLASS_FSI = 22,
  UTF8PROC_BIDI_CLASS_PDI = 23,
} utf8proc_bidi_class_t;
typedef enum {
  UTF8PROC_DECOMP_TYPE_FONT = 1,
  UTF8PROC_DECOMP_TYPE_NOBREAK = 2,
  UTF8PROC_DECOMP_TYPE_INITIAL = 3,
  UTF8PROC_DECOMP_TYPE_MEDIAL = 4,
  UTF8PROC_DECOMP_TYPE_FINAL = 5,
  UTF8PROC_DECOMP_TYPE_ISOLATED = 6,
  UTF8PROC_DECOMP_TYPE_CIRCLE = 7,
  UTF8PROC_DECOMP_TYPE_SUPER = 8,
  UTF8PROC_DECOMP_TYPE_SUB = 9,
  UTF8PROC_DECOMP_TYPE_VERTICAL = 10,
  UTF8PROC_DECOMP_TYPE_WIDE = 11,
  UTF8PROC_DECOMP_TYPE_NARROW = 12,
  UTF8PROC_DECOMP_TYPE_SMALL = 13,
  UTF8PROC_DECOMP_TYPE_SQUARE = 14,
  UTF8PROC_DECOMP_TYPE_FRACTION = 15,
  UTF8PROC_DECOMP_TYPE_COMPAT = 16,
} utf8proc_decomp_type_t;
typedef enum {
  UTF8PROC_BOUNDCLASS_START = 0,
  UTF8PROC_BOUNDCLASS_OTHER = 1,
  UTF8PROC_BOUNDCLASS_CR = 2,
  UTF8PROC_BOUNDCLASS_LF = 3,
  UTF8PROC_BOUNDCLASS_CONTROL = 4,
  UTF8PROC_BOUNDCLASS_EXTEND = 5,
  UTF8PROC_BOUNDCLASS_L = 6,
  UTF8PROC_BOUNDCLASS_V = 7,
  UTF8PROC_BOUNDCLASS_T = 8,
  UTF8PROC_BOUNDCLASS_LV = 9,
  UTF8PROC_BOUNDCLASS_LVT = 10,
  UTF8PROC_BOUNDCLASS_REGIONAL_INDICATOR = 11,
  UTF8PROC_BOUNDCLASS_SPACINGMARK = 12,
  UTF8PROC_BOUNDCLASS_PREPEND = 13,
  UTF8PROC_BOUNDCLASS_ZWJ = 14,
  UTF8PROC_BOUNDCLASS_E_BASE = 15,
  UTF8PROC_BOUNDCLASS_E_MODIFIER = 16,
  UTF8PROC_BOUNDCLASS_GLUE_AFTER_ZWJ = 17,
  UTF8PROC_BOUNDCLASS_E_BASE_GAZ = 18,
  UTF8PROC_BOUNDCLASS_EXTENDED_PICTOGRAPHIC = 19,
  UTF8PROC_BOUNDCLASS_E_ZWG = 20,
} utf8proc_boundclass_t;
typedef utf8proc_int32_t (*utf8proc_custom_func)(utf8proc_int32_t, void *);
extern const utf8proc_int8_t utf8proc_utf8class[256] __attribute__((visibility("default")));
const char *utf8proc_version(void) __attribute__((visibility("default")));
const char *utf8proc_unicode_version(void) __attribute__((visibility("default")));
const char *utf8proc_errmsg(utf8proc_ssize_t) __attribute__((visibility("default")));
utf8proc_ssize_t utf8proc_iterate(const utf8proc_uint8_t *, utf8proc_ssize_t, utf8proc_int32_t *) __attribute__((visibility("default")));
utf8proc_bool utf8proc_codepoint_valid(utf8proc_int32_t) __attribute__((visibility("default")));
utf8proc_ssize_t utf8proc_encode_char(utf8proc_int32_t, utf8proc_uint8_t *) __attribute__((visibility("default")));
const utf8proc_property_t *utf8proc_get_property(utf8proc_int32_t) __attribute__((visibility("default")));
utf8proc_ssize_t utf8proc_decompose_char(utf8proc_int32_t, utf8proc_int32_t *, utf8proc_ssize_t, utf8proc_option_t, int *) __attribute__((visibility("default")));
utf8proc_ssize_t utf8proc_decompose(const utf8proc_uint8_t *, utf8proc_ssize_t, utf8proc_int32_t *, utf8proc_ssize_t, utf8proc_option_t) __attribute__((visibility("default")));
utf8proc_ssize_t utf8proc_decompose_custom(const utf8proc_uint8_t *, utf8proc_ssize_t, utf8proc_int32_t *, utf8proc_ssize_t, utf8proc_option_t, utf8proc_custom_func, void *) __attribute__((visibility("default")));
utf8proc_ssize_t utf8proc_normalize_utf32(utf8proc_int32_t *, utf8proc_ssize_t, utf8proc_option_t) __attribute__((visibility("default")));
utf8proc_ssize_t utf8proc_reencode(utf8proc_int32_t *, utf8proc_ssize_t, utf8proc_option_t) __attribute__((visibility("default")));
utf8proc_bool utf8proc_grapheme_break_stateful(utf8proc_int32_t, utf8proc_int32_t, utf8proc_int32_t *) __attribute__((visibility("default")));
utf8proc_bool utf8proc_grapheme_break(utf8proc_int32_t, utf8proc_int32_t) __attribute__((visibility("default")));
utf8proc_int32_t utf8proc_tolower(utf8proc_int32_t) __attribute__((visibility("default")));
utf8proc_int32_t utf8proc_toupper(utf8proc_int32_t) __attribute__((visibility("default")));
utf8proc_int32_t utf8proc_totitle(utf8proc_int32_t) __attribute__((visibility("default")));
int utf8proc_islower(utf8proc_int32_t) __attribute__((visibility("default")));
int utf8proc_isupper(utf8proc_int32_t) __attribute__((visibility("default")));
int utf8proc_charwidth(utf8proc_int32_t) __attribute__((visibility("default")));
utf8proc_category_t utf8proc_category(utf8proc_int32_t) __attribute__((visibility("default")));
const char *utf8proc_category_string(utf8proc_int32_t) __attribute__((visibility("default")));
utf8proc_ssize_t utf8proc_map(const utf8proc_uint8_t *, utf8proc_ssize_t, utf8proc_uint8_t **, utf8proc_option_t) __attribute__((visibility("default")));
utf8proc_ssize_t utf8proc_map_custom(const utf8proc_uint8_t *, utf8proc_ssize_t, utf8proc_uint8_t **, utf8proc_option_t, utf8proc_custom_func, void *) __attribute__((visibility("default")));
utf8proc_uint8_t *utf8proc_NFD(const utf8proc_uint8_t *) __attribute__((visibility("default")));
utf8proc_uint8_t *utf8proc_NFC(const utf8proc_uint8_t *) __attribute__((visibility("default")));
utf8proc_uint8_t *utf8proc_NFKD(const utf8proc_uint8_t *) __attribute__((visibility("default")));
utf8proc_uint8_t *utf8proc_NFKC(const utf8proc_uint8_t *) __attribute__((visibility("default")));
utf8proc_uint8_t *utf8proc_NFKC_Casefold(const utf8proc_uint8_t *) __attribute__((visibility("default")));
]]
