local ffi = require("ffi")

ffi.cdef[[
typedef char FT_String;
typedef unsigned char FT_Byte;
typedef short unsigned int FT_UShort;
typedef short int FT_Short;
typedef int FT_Int;
typedef unsigned int FT_UInt;
typedef long int FT_Long;
typedef long unsigned int FT_ULong;
typedef int FT_Error;
typedef long int FT_Pos;
struct FT_Generic_ {
  void *data;
  void (*finalizer)(void *);
};
typedef struct FT_Generic_ FT_Generic;
typedef struct FT_ListNodeRec_ *FT_ListNode;
struct FT_ListNodeRec_ {
  FT_ListNode prev;
  FT_ListNode next;
  void *data;
};
typedef struct FT_ListRec_ *FT_List;
struct FT_ListRec_ {
  FT_ListNode head;
  FT_ListNode tail;
};
struct FT_BBox_ {
  FT_Pos xMin;
  FT_Pos yMin;
  FT_Pos xMax;
  FT_Pos yMax;
};
typedef struct FT_BBox_ FT_BBox;
struct FT_Bitmap_Size_ {
  FT_Short height;
  FT_Short width;
  FT_Pos size;
  FT_Pos x_ppem;
  FT_Pos y_ppem;
};
typedef struct FT_Bitmap_Size_ FT_Bitmap_Size;
struct FT_Bitmap_ {
  unsigned int rows;
  unsigned int width;
  int pitch;
  unsigned char *buffer;
  short unsigned int num_grays;
  unsigned char pixel_mode;
  unsigned char palette_mode;
  void *palette;
};
typedef struct FT_Bitmap_ FT_Bitmap;
struct FT_Vector_ {
  FT_Pos x;
  FT_Pos y;
};
typedef struct FT_Vector_ FT_Vector;
struct FT_Outline_ {
  short int n_contours;
  short int n_points;
  FT_Vector *points;
  char *tags;
  short int *contours;
  int flags;
};
typedef struct FT_Outline_ FT_Outline;
typedef struct FT_MemoryRec_ *FT_Memory;
struct FT_MemoryRec_ {
  void *user;
  void *(*alloc)(FT_Memory, long int);
  void (*free)(FT_Memory, void *);
  void *(*realloc)(FT_Memory, long int, long int, void *);
};
union FT_StreamDesc_ {
  long int value;
  void *pointer;
};
typedef union FT_StreamDesc_ FT_StreamDesc;
typedef struct FT_StreamRec_ *FT_Stream;
struct FT_StreamRec_ {
  unsigned char *base;
  long unsigned int size;
  long unsigned int pos;
  FT_StreamDesc descriptor;
  FT_StreamDesc pathname;
  long unsigned int (*read)(FT_Stream, long unsigned int, unsigned char *, long unsigned int);
  void (*close)(FT_Stream);
  FT_Memory memory;
  unsigned char *cursor;
  unsigned char *limit;
};
enum FT_Glyph_Format_ {
  FT_GLYPH_FORMAT_NONE = 0,
  FT_GLYPH_FORMAT_COMPOSITE = 1668246896,
  FT_GLYPH_FORMAT_BITMAP = 1651078259,
  FT_GLYPH_FORMAT_OUTLINE = 1869968492,
  FT_GLYPH_FORMAT_PLOTTER = 1886154612,
  FT_GLYPH_FORMAT_SVG = 1398163232,
};
typedef enum FT_Glyph_Format_ FT_Glyph_Format;
struct FT_LibraryRec_;
typedef struct FT_LibraryRec_ *FT_Library;
typedef struct FT_FaceRec_ *FT_Face;
typedef struct FT_Glyph_Metrics_ FT_Glyph_Metrics;
struct FT_Glyph_Metrics_ {
  FT_Pos width;
  FT_Pos height;
  FT_Pos horiBearingX;
  FT_Pos horiBearingY;
  FT_Pos horiAdvance;
  FT_Pos vertBearingX;
  FT_Pos vertBearingY;
  FT_Pos vertAdvance;
};
struct FT_SubGlyphRec_;
typedef struct FT_SubGlyphRec_ *FT_SubGlyph;
struct FT_Slot_InternalRec_;
typedef struct FT_Slot_InternalRec_ *FT_Slot_Internal;
typedef struct FT_GlyphSlotRec_ *FT_GlyphSlot;
struct FT_GlyphSlotRec_ {
  FT_Library library;
  FT_Face face;
  FT_GlyphSlot next;
  FT_UInt glyph_index;
  FT_Generic generic;
  FT_Glyph_Metrics metrics;
  long int linearHoriAdvance;
  long int linearVertAdvance;
  FT_Vector advance;
  FT_Glyph_Format format;
  FT_Bitmap bitmap;
  FT_Int bitmap_left;
  FT_Int bitmap_top;
  FT_Outline outline;
  FT_UInt num_subglyphs;
  FT_SubGlyph subglyphs;
  void *control_data;
  long int control_len;
  FT_Pos lsb_delta;
  FT_Pos rsb_delta;
  void *other;
  FT_Slot_Internal internal;
};
struct FT_Size_Metrics_ {
  FT_UShort x_ppem;
  FT_UShort y_ppem;
  long int x_scale;
  long int y_scale;
  FT_Pos ascender;
  FT_Pos descender;
  FT_Pos height;
  FT_Pos max_advance;
};
typedef struct FT_Size_Metrics_ FT_Size_Metrics;
typedef struct FT_Size_InternalRec_ *FT_Size_Internal;
struct FT_Size_InternalRec_;
typedef struct FT_SizeRec_ *FT_Size;
struct FT_SizeRec_ {
  FT_Face face;
  FT_Generic generic;
  FT_Size_Metrics metrics;
  FT_Size_Internal internal;
};
typedef struct FT_CharMapRec_ *FT_CharMap;
struct FT_DriverRec_;
typedef struct FT_DriverRec_ *FT_Driver;
struct FT_Face_InternalRec_;
typedef struct FT_Face_InternalRec_ *FT_Face_Internal;
struct FT_FaceRec_ {
  FT_Long num_faces;
  FT_Long face_index;
  FT_Long face_flags;
  FT_Long style_flags;
  FT_Long num_glyphs;
  FT_String *family_name;
  FT_String *style_name;
  FT_Int num_fixed_sizes;
  FT_Bitmap_Size *available_sizes;
  FT_Int num_charmaps;
  FT_CharMap *charmaps;
  FT_Generic generic;
  FT_BBox bbox;
  FT_UShort units_per_EM;
  FT_Short ascender;
  FT_Short descender;
  FT_Short height;
  FT_Short max_advance_width;
  FT_Short max_advance_height;
  FT_Short underline_position;
  FT_Short underline_thickness;
  FT_GlyphSlot glyph;
  FT_Size size;
  FT_CharMap charmap;
  FT_Driver driver;
  FT_Memory memory;
  FT_Stream stream;
  struct FT_ListRec_ sizes_list;
  FT_Generic autohint;
  void *extensions;
  FT_Face_Internal internal;
};
enum FT_Encoding_ {
  FT_ENCODING_NONE = 0,
  FT_ENCODING_MS_SYMBOL = 1937337698,
  FT_ENCODING_UNICODE = 1970170211,
  FT_ENCODING_SJIS = 1936353651,
  FT_ENCODING_PRC = 1734484000,
  FT_ENCODING_BIG5 = 1651074869,
  FT_ENCODING_WANSUNG = 2002873971,
  FT_ENCODING_JOHAB = 1785686113,
  FT_ENCODING_GB2312 = 1734484000,
  FT_ENCODING_MS_SJIS = 1936353651,
  FT_ENCODING_MS_GB2312 = 1734484000,
  FT_ENCODING_MS_BIG5 = 1651074869,
  FT_ENCODING_MS_WANSUNG = 2002873971,
  FT_ENCODING_MS_JOHAB = 1785686113,
  FT_ENCODING_ADOBE_STANDARD = 1094995778,
  FT_ENCODING_ADOBE_EXPERT = 1094992453,
  FT_ENCODING_ADOBE_CUSTOM = 1094992451,
  FT_ENCODING_ADOBE_LATIN_1 = 1818326065,
  FT_ENCODING_OLD_LATIN_2 = 1818326066,
  FT_ENCODING_APPLE_ROMAN = 1634889070,
};
typedef enum FT_Encoding_ FT_Encoding;
struct FT_CharMapRec_ {
  FT_Face face;
  FT_Encoding encoding;
  FT_UShort platform_id;
  FT_UShort encoding_id;
};
FT_Error FT_Init_FreeType(FT_Library *) __attribute__((visibility("default")));
FT_Error FT_Reference_Library(FT_Library) __attribute__((visibility("default")));
FT_Error FT_Done_Library(FT_Library) __attribute__((visibility("default")));
FT_Error FT_New_Face(FT_Library, const char *, FT_Long, FT_Face *) __attribute__((visibility("default")));
FT_Error FT_Set_Pixel_Sizes(FT_Face, FT_UInt, FT_UInt) __attribute__((visibility("default")));
FT_Error FT_Reference_Face(FT_Face) __attribute__((visibility("default")));
FT_Error FT_Done_Face(FT_Face) __attribute__((visibility("default")));
FT_Error FT_New_Size(FT_Face, FT_Size *) __attribute__((visibility("default")));
FT_Error FT_Done_Size(FT_Size) __attribute__((visibility("default")));
FT_Error FT_Activate_Size(FT_Size) __attribute__((visibility("default")));
FT_UInt FT_Get_Char_Index(FT_Face, FT_ULong) __attribute__((visibility("default")));
FT_Error FT_Load_Char(FT_Face, FT_ULong, int) __attribute__((visibility("default")));
FT_Error FT_Get_Kerning(FT_Face, FT_UInt, FT_UInt, FT_UInt, FT_Vector *) __attribute__((visibility("default")));
void FT_GlyphSlot_Embolden(FT_GlyphSlot) __attribute__((visibility("default")));
void FT_GlyphSlot_Oblique(FT_GlyphSlot) __attribute__((visibility("default")));
enum FT_Render_Mode_ {
  FT_RENDER_MODE_NORMAL = 0,
  FT_RENDER_MODE_LIGHT = 1,
  FT_RENDER_MODE_MONO = 2,
  FT_RENDER_MODE_LCD = 3,
  FT_RENDER_MODE_LCD_V = 4,
  FT_RENDER_MODE_SDF = 5,
  FT_RENDER_MODE_MAX = 6,
};
typedef enum FT_Render_Mode_ FT_Render_Mode;
FT_Error FT_Load_Glyph(FT_Face, FT_UInt, int) __attribute__((visibility("default")));
FT_Error FT_Render_Glyph(FT_GlyphSlot, FT_Render_Mode) __attribute__((visibility("default")));
FT_Error FT_Outline_Embolden(FT_Outline *, FT_Pos) __attribute__((visibility("default")));
void FT_Outline_Translate(const FT_Outline *, FT_Pos, FT_Pos) __attribute__((visibility("default")));
FT_Long FT_MulFix(FT_Long, FT_Long) __attribute__((visibility("default")));
FT_ULong FT_Get_First_Char(FT_Face, FT_UInt *) __attribute__((visibility("default")));
FT_ULong FT_Get_Next_Char(FT_Face, FT_ULong, FT_UInt *) __attribute__((visibility("default")));
static const int FT_LOAD_DEFAULT = 0;
static const int FT_LOAD_NO_SCALE = 1;
static const int FT_LOAD_NO_HINTING = 2;
static const int FT_LOAD_RENDER = 4;
static const int FT_LOAD_NO_BITMAP = 8;
static const int FT_LOAD_VERTICAL_LAYOUT = 16;
static const int FT_LOAD_FORCE_AUTOHINT = 32;
static const int FT_LOAD_CROP_BITMAP = 64;
static const int FT_LOAD_PEDANTIC = 128;
static const int FT_LOAD_IGNORE_GLOBAL_ADVANCE_WIDTH = 512;
static const int FT_LOAD_NO_RECURSE = 1024;
static const int FT_LOAD_IGNORE_TRANSFORM = 2048;
static const int FT_LOAD_MONOCHROME = 4096;
static const int FT_LOAD_LINEAR_DESIGN = 8192;
static const int FT_LOAD_SBITS_ONLY = 16384;
static const int FT_LOAD_NO_AUTOHINT = 32768;
static const int FT_LOAD_TARGET_NORMAL = 0;
static const int FT_LOAD_TARGET_LIGHT = 65536;
static const int FT_LOAD_TARGET_MONO = 131072;
static const int FT_LOAD_TARGET_LCD = 196608;
static const int FT_LOAD_TARGET_LCD_V = 262144;
static const int FT_FACE_FLAG_SCALABLE = 1;
static const int FT_FACE_FLAG_FIXED_SIZES = 2;
static const int FT_FACE_FLAG_FIXED_WIDTH = 4;
static const int FT_FACE_FLAG_HORIZONTAL = 16;
static const int FT_FACE_FLAG_VERTICAL = 32;
static const int FT_FACE_FLAG_SFNT = 8;
static const int FT_FACE_FLAG_KERNING = 64;
static const int FT_FACE_FLAG_MULTIPLE_MASTERS = 256;
static const int FT_FACE_FLAG_GLYPH_NAMES = 512;
static const int FT_FACE_FLAG_EXTERNAL_STREAM = 1024;
static const int FT_FACE_FLAG_FAST_GLYPHS = 128;
static const int FT_FACE_FLAG_HINTER = 2048;
static const int FT_STYLE_FLAG_BOLD = 2;
static const int FT_STYLE_FLAG_ITALIC = 1;
static const int FT_KERNING_DEFAULT = 0;
static const int FT_KERNING_UNFITTED = 1;
static const int FT_KERNING_UNSCALED = 2;
struct TT_OS2_ {
  FT_UShort version;
  FT_Short xAvgCharWidth;
  FT_UShort usWeightClass;
  FT_UShort usWidthClass;
  FT_UShort fsType;
  FT_Short ySubscriptXSize;
  FT_Short ySubscriptYSize;
  FT_Short ySubscriptXOffset;
  FT_Short ySubscriptYOffset;
  FT_Short ySuperscriptXSize;
  FT_Short ySuperscriptYSize;
  FT_Short ySuperscriptXOffset;
  FT_Short ySuperscriptYOffset;
  FT_Short yStrikeoutSize;
  FT_Short yStrikeoutPosition;
  FT_Short sFamilyClass;
  FT_Byte panose[10];
  FT_ULong ulUnicodeRange1;
  FT_ULong ulUnicodeRange2;
  FT_ULong ulUnicodeRange3;
  FT_ULong ulUnicodeRange4;
  signed char achVendID[4];
  FT_UShort fsSelection;
  FT_UShort usFirstCharIndex;
  FT_UShort usLastCharIndex;
  FT_Short sTypoAscender;
  FT_Short sTypoDescender;
  FT_Short sTypoLineGap;
  FT_UShort usWinAscent;
  FT_UShort usWinDescent;
  FT_ULong ulCodePageRange1;
  FT_ULong ulCodePageRange2;
  FT_Short sxHeight;
  FT_Short sCapHeight;
  FT_UShort usDefaultChar;
  FT_UShort usBreakChar;
  FT_UShort usMaxContext;
  FT_UShort usLowerOpticalPointSize;
  FT_UShort usUpperOpticalPointSize;
};
typedef struct TT_OS2_ TT_OS2;
enum FT_Sfnt_Tag_ {
  FT_SFNT_HEAD = 0,
  FT_SFNT_MAXP = 1,
  FT_SFNT_OS2 = 2,
  FT_SFNT_HHEA = 3,
  FT_SFNT_VHEA = 4,
  FT_SFNT_POST = 5,
  FT_SFNT_PCLT = 6,
  FT_SFNT_MAX = 7,
};
typedef enum FT_Sfnt_Tag_ FT_Sfnt_Tag;
void *FT_Get_Sfnt_Table(FT_Face, FT_Sfnt_Tag) __attribute__((visibility("default")));
struct FT_SfntName_ {
  FT_UShort platform_id;
  FT_UShort encoding_id;
  FT_UShort language_id;
  FT_UShort name_id;
  FT_Byte *string;
  FT_UInt string_len;
};
typedef struct FT_SfntName_ FT_SfntName;
static const int TT_NAME_ID_COPYRIGHT = 0;
static const int TT_NAME_ID_FONT_FAMILY = 1;
static const int TT_NAME_ID_FONT_SUBFAMILY = 2;
static const int TT_NAME_ID_UNIQUE_ID = 3;
static const int TT_NAME_ID_FULL_NAME = 4;
static const int TT_NAME_ID_VERSION_STRING = 5;
static const int TT_NAME_ID_PS_NAME = 6;
static const int TT_NAME_ID_TRADEMARK = 7;
static const int TT_NAME_ID_MANUFACTURER = 8;
static const int TT_NAME_ID_DESIGNER = 9;
static const int TT_NAME_ID_DESCRIPTION = 10;
static const int TT_NAME_ID_VENDOR_URL = 11;
static const int TT_NAME_ID_DESIGNER_URL = 12;
static const int TT_NAME_ID_LICENSE = 13;
static const int TT_NAME_ID_LICENSE_URL = 14;
static const int TT_NAME_ID_PREFERRED_FAMILY = 16;
static const int TT_NAME_ID_PREFERRED_SUBFAMILY = 17;
static const int TT_NAME_ID_MAC_FULL_NAME = 18;
static const int TT_NAME_ID_SAMPLE_TEXT = 19;
static const int TT_NAME_ID_CID_FINDFONT_NAME = 20;
static const int TT_NAME_ID_WWS_FAMILY = 21;
static const int TT_NAME_ID_WWS_SUBFAMILY = 22;
FT_UInt FT_Get_Sfnt_Name_Count(FT_Face) __attribute__((visibility("default")));
FT_Error FT_Get_Sfnt_Name(FT_Face, FT_UInt, FT_SfntName *) __attribute__((visibility("default")));
]]
