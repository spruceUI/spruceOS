local ffi = require("ffi")

ffi.cdef[[
typedef struct {
  float x0;
  float y0;
  float x1;
  float y1;
} BBox;
typedef struct Boxa BOXA;
typedef struct Numa NUMA;
typedef struct Pix PIX;
typedef struct {
  double x;
  double y;
} POINT2D;
typedef struct {
  int srcpageno;
  int srcwidth;
  int srcheight;
  double srcdpiw;
  double srcdpih;
  int srcrot;
  POINT2D coords[3];
} WRECTMAP;
typedef struct {
  WRECTMAP *wrectmap;
  int n;
  int na;
} WRECTMAPS;
typedef struct {
  int red[256];
  int green[256];
  int blue[256];
  unsigned char *data;
  int width;
  int height;
  int bpp;
  int size_allocated;
  int type;
} WILLUSBITMAP;
typedef struct {
  int ch;
  int c2;
  int r1;
  int r2;
} HYPHENINFO;
typedef struct {
  int c1;
  int c2;
  int r1;
  int r2;
  int rowbase;
  int gap;
  int gapblank;
  int rowheight;
  int capheight;
  int h5050;
  int lcheight;
  int type;
  double rat;
  HYPHENINFO hyphen;
} TEXTROW;
typedef struct {
  TEXTROW *textrow;
  int n;
  int na;
} TEXTROWS;
typedef struct {
  int r1;
  int r2;
  int c1;
  int c2;
  TEXTROWS textrows;
  TEXTROW bbox;
  WRECTMAPS *wrectmaps;
  struct {
    int n;
    struct {
      int row;
      int col;
      int type;
    } k2pagebreakmark[32];
  } *k2pagebreakmarks;
  int k2pagebreakmarks_allocated;
  int bgcolor;
  int dpi;
  int pageno;
  int rotdeg;
  int *colcount;
  int *rowcount;
  WILLUSBITMAP *bmp;
  WILLUSBITMAP *bmp8;
  WILLUSBITMAP *marked;
} BMPREGION;
typedef struct {
  BMPREGION bmpregion;
  int notes;
  int fullspan;
  int level;
} PAGEREGION;
typedef struct {
  PAGEREGION *pageregion;
  int n;
  int na;
} PAGEREGIONS;
struct KOPTContext {
  int trim;
  int wrap;
  int white;
  int indent;
  int rotate;
  int columns;
  int offset_x;
  int offset_y;
  int dev_dpi;
  int dev_width;
  int dev_height;
  int page_width;
  int page_height;
  int straighten;
  int justification;
  int read_max_width;
  int read_max_height;
  int writing_direction;
  double zoom;
  double margin;
  double quality;
  double contrast;
  double defect_size;
  double line_spacing;
  double word_spacing;
  double shrink_factor;
  int precache;
  int debug;
  int cjkchar;
  BOXA *rboxa;
  NUMA *rnai;
  BOXA *nboxa;
  NUMA *nnai;
  WRECTMAPS rectmaps;
  PAGEREGIONS pageregions;
  BBox bbox;
  char *language;
  WILLUSBITMAP dst;
  WILLUSBITMAP src;
};
typedef struct KOPTContext KOPTContext;
void bmp_init(WILLUSBITMAP *);
void bmp_free(WILLUSBITMAP *);
int bmp_alloc(WILLUSBITMAP *);
int bmp_copy(WILLUSBITMAP *, WILLUSBITMAP *);
unsigned char *bmp_rowptr_from_top(WILLUSBITMAP *, int);
void wrectmaps_init(WRECTMAPS *);
void wrectmaps_free(WRECTMAPS *);
int wrectmap_inside(WRECTMAP *, int, int);
void k2pdfopt_get_reflowed_word_boxes(KOPTContext *, WILLUSBITMAP *, int, int, int, int);
void k2pdfopt_get_native_word_boxes(KOPTContext *, WILLUSBITMAP *, int, int, int, int);
void k2pdfopt_tocr_single_word(WILLUSBITMAP *, int, int, int, int, char *, int, char *, char *, int, int, int);
void k2pdfopt_reflow_bmp(KOPTContext *);
void k2pdfopt_tocr_end();
void pageregions_init(PAGEREGIONS *);
void pageregions_free(PAGEREGIONS *);
void k2pdfopt_crop_bmp(KOPTContext *);
void k2pdfopt_optimize_bmp(KOPTContext *);
void pixmap_to_bmp(WILLUSBITMAP *, unsigned char *, int);
PIX *bitmap2pix(WILLUSBITMAP *, int, int, int, int);
]]
