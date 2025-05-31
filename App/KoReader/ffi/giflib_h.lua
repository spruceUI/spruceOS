local ffi = require("ffi")

ffi.cdef[[
static const int GIF_OK = 1;
static const int GIF_ERROR = 0;
typedef int GifWord;
typedef unsigned char GifByteType;
typedef struct GifColorType GifColorType;
struct GifColorType {
  GifByteType Red;
  GifByteType Green;
  GifByteType Blue;
};
typedef struct ColorMapObject ColorMapObject;
struct ColorMapObject {
  int ColorCount;
  int BitsPerPixel;
  bool SortFlag;
  GifColorType *Colors;
};
typedef struct GifImageDesc GifImageDesc;
struct GifImageDesc {
  GifWord Left;
  GifWord Top;
  GifWord Width;
  GifWord Height;
  bool Interlace;
  ColorMapObject *ColorMap;
};
typedef struct ExtensionBlock ExtensionBlock;
struct ExtensionBlock {
  int ByteCount;
  GifByteType *Bytes;
  int Function;
};
typedef struct GraphicsControlBlock GraphicsControlBlock;
struct GraphicsControlBlock {
  int DisposalMode;
  bool UserInputFlag;
  int DelayTime;
  int TransparentColor;
};
typedef struct SavedImage SavedImage;
struct SavedImage {
  GifImageDesc ImageDesc;
  GifByteType *RasterBits;
  int ExtensionBlockCount;
  ExtensionBlock *ExtensionBlocks;
};
typedef struct GifFileType GifFileType;
struct GifFileType {
  GifWord SWidth;
  GifWord SHeight;
  GifWord SColorResolution;
  GifWord SBackGroundColor;
  GifByteType AspectByte;
  ColorMapObject *SColorMap;
  int ImageCount;
  GifImageDesc Image;
  SavedImage *SavedImages;
  int ExtensionBlockCount;
  ExtensionBlock *ExtensionBlocks;
  int Error;
  void *UserData;
  void *Private;
};
GifFileType *DGifOpenFileName(const char *, int *);
GifFileType *DGifOpenFileHandle(int, int *);
int DGifCloseFile(GifFileType *, int *);
int DGifSlurp(GifFileType *);
const char *GifErrorString(int);
int DGifSavedExtensionToGCB(GifFileType *, int, GraphicsControlBlock *);
static const int DISPOSAL_UNSPECIFIED = 0;
static const int DISPOSE_DO_NOT = 1;
static const int DISPOSE_BACKGROUND = 2;
static const int DISPOSE_PREVIOUS = 3;
static const int NO_TRANSPARENT_COLOR = -1;
typedef int (*InputFunc)(GifFileType *, GifByteType *, int);
GifFileType *DGifOpen(void *, InputFunc, int *);
]]
