local ffi = require("ffi")

ffi.cdef[[
typedef uint64_t Uint64;
typedef int64_t Sint64;
typedef uint32_t Uint32;
typedef int32_t Sint32;
typedef uint16_t Uint16;
typedef int16_t Sint16;
typedef uint8_t Uint8;
typedef int8_t Sint8;
typedef enum {
  SDL_SCANCODE_UNKNOWN = 0,
  SDL_SCANCODE_A = 4,
  SDL_SCANCODE_B = 5,
  SDL_SCANCODE_C = 6,
  SDL_SCANCODE_D = 7,
  SDL_SCANCODE_E = 8,
  SDL_SCANCODE_F = 9,
  SDL_SCANCODE_G = 10,
  SDL_SCANCODE_H = 11,
  SDL_SCANCODE_I = 12,
  SDL_SCANCODE_J = 13,
  SDL_SCANCODE_K = 14,
  SDL_SCANCODE_L = 15,
  SDL_SCANCODE_M = 16,
  SDL_SCANCODE_N = 17,
  SDL_SCANCODE_O = 18,
  SDL_SCANCODE_P = 19,
  SDL_SCANCODE_Q = 20,
  SDL_SCANCODE_R = 21,
  SDL_SCANCODE_S = 22,
  SDL_SCANCODE_T = 23,
  SDL_SCANCODE_U = 24,
  SDL_SCANCODE_V = 25,
  SDL_SCANCODE_W = 26,
  SDL_SCANCODE_X = 27,
  SDL_SCANCODE_Y = 28,
  SDL_SCANCODE_Z = 29,
  SDL_SCANCODE_1 = 30,
  SDL_SCANCODE_2 = 31,
  SDL_SCANCODE_3 = 32,
  SDL_SCANCODE_4 = 33,
  SDL_SCANCODE_5 = 34,
  SDL_SCANCODE_6 = 35,
  SDL_SCANCODE_7 = 36,
  SDL_SCANCODE_8 = 37,
  SDL_SCANCODE_9 = 38,
  SDL_SCANCODE_0 = 39,
  SDL_SCANCODE_RETURN = 40,
  SDL_SCANCODE_ESCAPE = 41,
  SDL_SCANCODE_BACKSPACE = 42,
  SDL_SCANCODE_TAB = 43,
  SDL_SCANCODE_SPACE = 44,
  SDL_SCANCODE_MINUS = 45,
  SDL_SCANCODE_EQUALS = 46,
  SDL_SCANCODE_LEFTBRACKET = 47,
  SDL_SCANCODE_RIGHTBRACKET = 48,
  SDL_SCANCODE_BACKSLASH = 49,
  SDL_SCANCODE_NONUSHASH = 50,
  SDL_SCANCODE_SEMICOLON = 51,
  SDL_SCANCODE_APOSTROPHE = 52,
  SDL_SCANCODE_GRAVE = 53,
  SDL_SCANCODE_COMMA = 54,
  SDL_SCANCODE_PERIOD = 55,
  SDL_SCANCODE_SLASH = 56,
  SDL_SCANCODE_CAPSLOCK = 57,
  SDL_SCANCODE_F1 = 58,
  SDL_SCANCODE_F2 = 59,
  SDL_SCANCODE_F3 = 60,
  SDL_SCANCODE_F4 = 61,
  SDL_SCANCODE_F5 = 62,
  SDL_SCANCODE_F6 = 63,
  SDL_SCANCODE_F7 = 64,
  SDL_SCANCODE_F8 = 65,
  SDL_SCANCODE_F9 = 66,
  SDL_SCANCODE_F10 = 67,
  SDL_SCANCODE_F11 = 68,
  SDL_SCANCODE_F12 = 69,
  SDL_SCANCODE_PRINTSCREEN = 70,
  SDL_SCANCODE_SCROLLLOCK = 71,
  SDL_SCANCODE_PAUSE = 72,
  SDL_SCANCODE_INSERT = 73,
  SDL_SCANCODE_HOME = 74,
  SDL_SCANCODE_PAGEUP = 75,
  SDL_SCANCODE_DELETE = 76,
  SDL_SCANCODE_END = 77,
  SDL_SCANCODE_PAGEDOWN = 78,
  SDL_SCANCODE_RIGHT = 79,
  SDL_SCANCODE_LEFT = 80,
  SDL_SCANCODE_DOWN = 81,
  SDL_SCANCODE_UP = 82,
  SDL_SCANCODE_NUMLOCKCLEAR = 83,
  SDL_SCANCODE_KP_DIVIDE = 84,
  SDL_SCANCODE_KP_MULTIPLY = 85,
  SDL_SCANCODE_KP_MINUS = 86,
  SDL_SCANCODE_KP_PLUS = 87,
  SDL_SCANCODE_KP_ENTER = 88,
  SDL_SCANCODE_KP_1 = 89,
  SDL_SCANCODE_KP_2 = 90,
  SDL_SCANCODE_KP_3 = 91,
  SDL_SCANCODE_KP_4 = 92,
  SDL_SCANCODE_KP_5 = 93,
  SDL_SCANCODE_KP_6 = 94,
  SDL_SCANCODE_KP_7 = 95,
  SDL_SCANCODE_KP_8 = 96,
  SDL_SCANCODE_KP_9 = 97,
  SDL_SCANCODE_KP_0 = 98,
  SDL_SCANCODE_KP_PERIOD = 99,
  SDL_SCANCODE_NONUSBACKSLASH = 100,
  SDL_SCANCODE_APPLICATION = 101,
  SDL_SCANCODE_POWER = 102,
  SDL_SCANCODE_KP_EQUALS = 103,
  SDL_SCANCODE_F13 = 104,
  SDL_SCANCODE_F14 = 105,
  SDL_SCANCODE_F15 = 106,
  SDL_SCANCODE_F16 = 107,
  SDL_SCANCODE_F17 = 108,
  SDL_SCANCODE_F18 = 109,
  SDL_SCANCODE_F19 = 110,
  SDL_SCANCODE_F20 = 111,
  SDL_SCANCODE_F21 = 112,
  SDL_SCANCODE_F22 = 113,
  SDL_SCANCODE_F23 = 114,
  SDL_SCANCODE_F24 = 115,
  SDL_SCANCODE_EXECUTE = 116,
  SDL_SCANCODE_HELP = 117,
  SDL_SCANCODE_MENU = 118,
  SDL_SCANCODE_SELECT = 119,
  SDL_SCANCODE_STOP = 120,
  SDL_SCANCODE_AGAIN = 121,
  SDL_SCANCODE_UNDO = 122,
  SDL_SCANCODE_CUT = 123,
  SDL_SCANCODE_COPY = 124,
  SDL_SCANCODE_PASTE = 125,
  SDL_SCANCODE_FIND = 126,
  SDL_SCANCODE_MUTE = 127,
  SDL_SCANCODE_VOLUMEUP = 128,
  SDL_SCANCODE_VOLUMEDOWN = 129,
  SDL_SCANCODE_KP_COMMA = 133,
  SDL_SCANCODE_KP_EQUALSAS400 = 134,
  SDL_SCANCODE_INTERNATIONAL1 = 135,
  SDL_SCANCODE_INTERNATIONAL2 = 136,
  SDL_SCANCODE_INTERNATIONAL3 = 137,
  SDL_SCANCODE_INTERNATIONAL4 = 138,
  SDL_SCANCODE_INTERNATIONAL5 = 139,
  SDL_SCANCODE_INTERNATIONAL6 = 140,
  SDL_SCANCODE_INTERNATIONAL7 = 141,
  SDL_SCANCODE_INTERNATIONAL8 = 142,
  SDL_SCANCODE_INTERNATIONAL9 = 143,
  SDL_SCANCODE_LANG1 = 144,
  SDL_SCANCODE_LANG2 = 145,
  SDL_SCANCODE_LANG3 = 146,
  SDL_SCANCODE_LANG4 = 147,
  SDL_SCANCODE_LANG5 = 148,
  SDL_SCANCODE_LANG6 = 149,
  SDL_SCANCODE_LANG7 = 150,
  SDL_SCANCODE_LANG8 = 151,
  SDL_SCANCODE_LANG9 = 152,
  SDL_SCANCODE_ALTERASE = 153,
  SDL_SCANCODE_SYSREQ = 154,
  SDL_SCANCODE_CANCEL = 155,
  SDL_SCANCODE_CLEAR = 156,
  SDL_SCANCODE_PRIOR = 157,
  SDL_SCANCODE_RETURN2 = 158,
  SDL_SCANCODE_SEPARATOR = 159,
  SDL_SCANCODE_OUT = 160,
  SDL_SCANCODE_OPER = 161,
  SDL_SCANCODE_CLEARAGAIN = 162,
  SDL_SCANCODE_CRSEL = 163,
  SDL_SCANCODE_EXSEL = 164,
  SDL_SCANCODE_KP_00 = 176,
  SDL_SCANCODE_KP_000 = 177,
  SDL_SCANCODE_THOUSANDSSEPARATOR = 178,
  SDL_SCANCODE_DECIMALSEPARATOR = 179,
  SDL_SCANCODE_CURRENCYUNIT = 180,
  SDL_SCANCODE_CURRENCYSUBUNIT = 181,
  SDL_SCANCODE_KP_LEFTPAREN = 182,
  SDL_SCANCODE_KP_RIGHTPAREN = 183,
  SDL_SCANCODE_KP_LEFTBRACE = 184,
  SDL_SCANCODE_KP_RIGHTBRACE = 185,
  SDL_SCANCODE_KP_TAB = 186,
  SDL_SCANCODE_KP_BACKSPACE = 187,
  SDL_SCANCODE_KP_A = 188,
  SDL_SCANCODE_KP_B = 189,
  SDL_SCANCODE_KP_C = 190,
  SDL_SCANCODE_KP_D = 191,
  SDL_SCANCODE_KP_E = 192,
  SDL_SCANCODE_KP_F = 193,
  SDL_SCANCODE_KP_XOR = 194,
  SDL_SCANCODE_KP_POWER = 195,
  SDL_SCANCODE_KP_PERCENT = 196,
  SDL_SCANCODE_KP_LESS = 197,
  SDL_SCANCODE_KP_GREATER = 198,
  SDL_SCANCODE_KP_AMPERSAND = 199,
  SDL_SCANCODE_KP_DBLAMPERSAND = 200,
  SDL_SCANCODE_KP_VERTICALBAR = 201,
  SDL_SCANCODE_KP_DBLVERTICALBAR = 202,
  SDL_SCANCODE_KP_COLON = 203,
  SDL_SCANCODE_KP_HASH = 204,
  SDL_SCANCODE_KP_SPACE = 205,
  SDL_SCANCODE_KP_AT = 206,
  SDL_SCANCODE_KP_EXCLAM = 207,
  SDL_SCANCODE_KP_MEMSTORE = 208,
  SDL_SCANCODE_KP_MEMRECALL = 209,
  SDL_SCANCODE_KP_MEMCLEAR = 210,
  SDL_SCANCODE_KP_MEMADD = 211,
  SDL_SCANCODE_KP_MEMSUBTRACT = 212,
  SDL_SCANCODE_KP_MEMMULTIPLY = 213,
  SDL_SCANCODE_KP_MEMDIVIDE = 214,
  SDL_SCANCODE_KP_PLUSMINUS = 215,
  SDL_SCANCODE_KP_CLEAR = 216,
  SDL_SCANCODE_KP_CLEARENTRY = 217,
  SDL_SCANCODE_KP_BINARY = 218,
  SDL_SCANCODE_KP_OCTAL = 219,
  SDL_SCANCODE_KP_DECIMAL = 220,
  SDL_SCANCODE_KP_HEXADECIMAL = 221,
  SDL_SCANCODE_LCTRL = 224,
  SDL_SCANCODE_LSHIFT = 225,
  SDL_SCANCODE_LALT = 226,
  SDL_SCANCODE_LGUI = 227,
  SDL_SCANCODE_RCTRL = 228,
  SDL_SCANCODE_RSHIFT = 229,
  SDL_SCANCODE_RALT = 230,
  SDL_SCANCODE_RGUI = 231,
  SDL_SCANCODE_MODE = 257,
  SDL_SCANCODE_AUDIONEXT = 258,
  SDL_SCANCODE_AUDIOPREV = 259,
  SDL_SCANCODE_AUDIOSTOP = 260,
  SDL_SCANCODE_AUDIOPLAY = 261,
  SDL_SCANCODE_AUDIOMUTE = 262,
  SDL_SCANCODE_MEDIASELECT = 263,
  SDL_SCANCODE_WWW = 264,
  SDL_SCANCODE_MAIL = 265,
  SDL_SCANCODE_CALCULATOR = 266,
  SDL_SCANCODE_COMPUTER = 267,
  SDL_SCANCODE_AC_SEARCH = 268,
  SDL_SCANCODE_AC_HOME = 269,
  SDL_SCANCODE_AC_BACK = 270,
  SDL_SCANCODE_AC_FORWARD = 271,
  SDL_SCANCODE_AC_STOP = 272,
  SDL_SCANCODE_AC_REFRESH = 273,
  SDL_SCANCODE_AC_BOOKMARKS = 274,
  SDL_SCANCODE_BRIGHTNESSDOWN = 275,
  SDL_SCANCODE_BRIGHTNESSUP = 276,
  SDL_SCANCODE_DISPLAYSWITCH = 277,
  SDL_SCANCODE_KBDILLUMTOGGLE = 278,
  SDL_SCANCODE_KBDILLUMDOWN = 279,
  SDL_SCANCODE_KBDILLUMUP = 280,
  SDL_SCANCODE_EJECT = 281,
  SDL_SCANCODE_SLEEP = 282,
  SDL_SCANCODE_APP1 = 283,
  SDL_SCANCODE_APP2 = 284,
  SDL_SCANCODE_AUDIOREWIND = 285,
  SDL_SCANCODE_AUDIOFASTFORWARD = 286,
  SDL_SCANCODE_SOFTLEFT = 287,
  SDL_SCANCODE_SOFTRIGHT = 288,
  SDL_SCANCODE_CALL = 289,
  SDL_SCANCODE_ENDCALL = 290,
  SDL_NUM_SCANCODES = 512,
} SDL_Scancode;
struct SDL_Keysym {
  SDL_Scancode scancode;
  int sym;
  Uint16 mod;
  Uint32 unused;
};
typedef struct SDL_Keysym SDL_Keysym;
void SDL_StartTextInput(void) __attribute__((visibility("default")));
void SDL_StopTextInput(void) __attribute__((visibility("default")));
typedef enum {
  SDL_FIRSTEVENT = 0,
  SDL_QUIT = 256,
  SDL_APP_TERMINATING = 257,
  SDL_APP_LOWMEMORY = 258,
  SDL_APP_WILLENTERBACKGROUND = 259,
  SDL_APP_DIDENTERBACKGROUND = 260,
  SDL_APP_WILLENTERFOREGROUND = 261,
  SDL_APP_DIDENTERFOREGROUND = 262,
  SDL_LOCALECHANGED = 263,
  SDL_DISPLAYEVENT = 336,
  SDL_WINDOWEVENT = 512,
  SDL_SYSWMEVENT = 513,
  SDL_KEYDOWN = 768,
  SDL_KEYUP = 769,
  SDL_TEXTEDITING = 770,
  SDL_TEXTINPUT = 771,
  SDL_KEYMAPCHANGED = 772,
  SDL_TEXTEDITING_EXT = 773,
  SDL_MOUSEMOTION = 1024,
  SDL_MOUSEBUTTONDOWN = 1025,
  SDL_MOUSEBUTTONUP = 1026,
  SDL_MOUSEWHEEL = 1027,
  SDL_JOYAXISMOTION = 1536,
  SDL_JOYBALLMOTION = 1537,
  SDL_JOYHATMOTION = 1538,
  SDL_JOYBUTTONDOWN = 1539,
  SDL_JOYBUTTONUP = 1540,
  SDL_JOYDEVICEADDED = 1541,
  SDL_JOYDEVICEREMOVED = 1542,
  SDL_JOYBATTERYUPDATED = 1543,
  SDL_CONTROLLERAXISMOTION = 1616,
  SDL_CONTROLLERBUTTONDOWN = 1617,
  SDL_CONTROLLERBUTTONUP = 1618,
  SDL_CONTROLLERDEVICEADDED = 1619,
  SDL_CONTROLLERDEVICEREMOVED = 1620,
  SDL_CONTROLLERDEVICEREMAPPED = 1621,
  SDL_CONTROLLERTOUCHPADDOWN = 1622,
  SDL_CONTROLLERTOUCHPADMOTION = 1623,
  SDL_CONTROLLERTOUCHPADUP = 1624,
  SDL_CONTROLLERSENSORUPDATE = 1625,
  SDL_FINGERDOWN = 1792,
  SDL_FINGERUP = 1793,
  SDL_FINGERMOTION = 1794,
  SDL_DOLLARGESTURE = 2048,
  SDL_DOLLARRECORD = 2049,
  SDL_MULTIGESTURE = 2050,
  SDL_CLIPBOARDUPDATE = 2304,
  SDL_DROPFILE = 4096,
  SDL_DROPTEXT = 4097,
  SDL_DROPBEGIN = 4098,
  SDL_DROPCOMPLETE = 4099,
  SDL_AUDIODEVICEADDED = 4352,
  SDL_AUDIODEVICEREMOVED = 4353,
  SDL_SENSORUPDATE = 4608,
  SDL_RENDER_TARGETS_RESET = 8192,
  SDL_RENDER_DEVICE_RESET = 8193,
  SDL_POLLSENTINEL = 32512,
  SDL_USEREVENT = 32768,
  SDL_LASTEVENT = 65535,
} SDL_EventType;
struct _SDL_Joystick;
typedef struct _SDL_Joystick SDL_Joystick;
typedef struct {
  Uint8 data[16];
} SDL_JoystickGUID;
typedef int32_t SDL_JoystickID;
typedef enum {
  SDL_JOYSTICK_POWER_UNKNOWN = -1,
  SDL_JOYSTICK_POWER_EMPTY = 0,
  SDL_JOYSTICK_POWER_LOW = 1,
  SDL_JOYSTICK_POWER_MEDIUM = 2,
  SDL_JOYSTICK_POWER_FULL = 3,
  SDL_JOYSTICK_POWER_WIRED = 4,
  SDL_JOYSTICK_POWER_MAX = 5,
} SDL_JoystickPowerLevel;
typedef int64_t SDL_TouchID;
typedef int64_t SDL_FingerID;
typedef int64_t SDL_GestureID;
struct SDL_Finger {
  SDL_FingerID id;
  float x;
  float y;
  float pressure;
};
typedef struct SDL_Finger SDL_Finger;
struct SDL_CommonEvent {
  Uint32 type;
  Uint32 timestamp;
};
typedef struct SDL_CommonEvent SDL_CommonEvent;
struct SDL_DisplayEvent {
  Uint32 type;
  Uint32 timestamp;
  Uint32 display;
  Uint8 event;
  Uint8 padding1;
  Uint8 padding2;
  Uint8 padding3;
  Sint32 data1;
};
typedef struct SDL_DisplayEvent SDL_DisplayEvent;
struct SDL_WindowEvent {
  Uint32 type;
  Uint32 timestamp;
  Uint32 windowID;
  Uint8 event;
  Uint8 padding1;
  Uint8 padding2;
  Uint8 padding3;
  Sint32 data1;
  Sint32 data2;
};
typedef struct SDL_WindowEvent SDL_WindowEvent;
typedef enum {
  SDL_WINDOWEVENT_NONE = 0,
  SDL_WINDOWEVENT_SHOWN = 1,
  SDL_WINDOWEVENT_HIDDEN = 2,
  SDL_WINDOWEVENT_EXPOSED = 3,
  SDL_WINDOWEVENT_MOVED = 4,
  SDL_WINDOWEVENT_RESIZED = 5,
  SDL_WINDOWEVENT_SIZE_CHANGED = 6,
  SDL_WINDOWEVENT_MINIMIZED = 7,
  SDL_WINDOWEVENT_MAXIMIZED = 8,
  SDL_WINDOWEVENT_RESTORED = 9,
  SDL_WINDOWEVENT_ENTER = 10,
  SDL_WINDOWEVENT_LEAVE = 11,
  SDL_WINDOWEVENT_FOCUS_GAINED = 12,
  SDL_WINDOWEVENT_FOCUS_LOST = 13,
  SDL_WINDOWEVENT_CLOSE = 14,
  SDL_WINDOWEVENT_TAKE_FOCUS = 15,
  SDL_WINDOWEVENT_HIT_TEST = 16,
  SDL_WINDOWEVENT_ICCPROF_CHANGED = 17,
  SDL_WINDOWEVENT_DISPLAY_CHANGED = 18,
} SDL_WindowEventID;
struct SDL_KeyboardEvent {
  Uint32 type;
  Uint32 timestamp;
  Uint32 windowID;
  Uint8 state;
  Uint8 repeat;
  Uint8 padding2;
  Uint8 padding3;
  SDL_Keysym keysym;
};
typedef struct SDL_KeyboardEvent SDL_KeyboardEvent;
struct SDL_TextEditingEvent {
  Uint32 type;
  Uint32 timestamp;
  Uint32 windowID;
  char text[32];
  Sint32 start;
  Sint32 length;
};
typedef struct SDL_TextEditingEvent SDL_TextEditingEvent;
struct SDL_TextEditingExtEvent {
  Uint32 type;
  Uint32 timestamp;
  Uint32 windowID;
  char *text;
  Sint32 start;
  Sint32 length;
};
typedef struct SDL_TextEditingExtEvent SDL_TextEditingExtEvent;
struct SDL_TextInputEvent {
  Uint32 type;
  Uint32 timestamp;
  Uint32 windowID;
  char text[32];
};
typedef struct SDL_TextInputEvent SDL_TextInputEvent;
struct SDL_MouseMotionEvent {
  Uint32 type;
  Uint32 timestamp;
  Uint32 windowID;
  Uint32 which;
  Uint32 state;
  Sint32 x;
  Sint32 y;
  Sint32 xrel;
  Sint32 yrel;
};
typedef struct SDL_MouseMotionEvent SDL_MouseMotionEvent;
struct SDL_MouseButtonEvent {
  Uint32 type;
  Uint32 timestamp;
  Uint32 windowID;
  Uint32 which;
  Uint8 button;
  Uint8 state;
  Uint8 clicks;
  Uint8 padding1;
  Sint32 x;
  Sint32 y;
};
typedef struct SDL_MouseButtonEvent SDL_MouseButtonEvent;
struct SDL_MouseWheelEvent {
  Uint32 type;
  Uint32 timestamp;
  Uint32 windowID;
  Uint32 which;
  Sint32 x;
  Sint32 y;
  Uint32 direction;
  float preciseX;
  float preciseY;
  Sint32 mouseX;
  Sint32 mouseY;
};
typedef struct SDL_MouseWheelEvent SDL_MouseWheelEvent;
struct SDL_JoyAxisEvent {
  Uint32 type;
  Uint32 timestamp;
  SDL_JoystickID which;
  Uint8 axis;
  Uint8 padding1;
  Uint8 padding2;
  Uint8 padding3;
  Sint16 value;
  Uint16 padding4;
};
typedef struct SDL_JoyAxisEvent SDL_JoyAxisEvent;
struct SDL_JoyBallEvent {
  Uint32 type;
  Uint32 timestamp;
  SDL_JoystickID which;
  Uint8 ball;
  Uint8 padding1;
  Uint8 padding2;
  Uint8 padding3;
  Sint16 xrel;
  Sint16 yrel;
};
typedef struct SDL_JoyBallEvent SDL_JoyBallEvent;
struct SDL_JoyHatEvent {
  Uint32 type;
  Uint32 timestamp;
  SDL_JoystickID which;
  Uint8 hat;
  Uint8 value;
  Uint8 padding1;
  Uint8 padding2;
};
typedef struct SDL_JoyHatEvent SDL_JoyHatEvent;
struct SDL_JoyButtonEvent {
  Uint32 type;
  Uint32 timestamp;
  SDL_JoystickID which;
  Uint8 button;
  Uint8 state;
  Uint8 padding1;
  Uint8 padding2;
};
typedef struct SDL_JoyButtonEvent SDL_JoyButtonEvent;
struct SDL_JoyDeviceEvent {
  Uint32 type;
  Uint32 timestamp;
  Sint32 which;
};
typedef struct SDL_JoyDeviceEvent SDL_JoyDeviceEvent;
struct SDL_JoyBatteryEvent {
  Uint32 type;
  Uint32 timestamp;
  SDL_JoystickID which;
  SDL_JoystickPowerLevel level;
};
typedef struct SDL_JoyBatteryEvent SDL_JoyBatteryEvent;
struct SDL_ControllerAxisEvent {
  Uint32 type;
  Uint32 timestamp;
  SDL_JoystickID which;
  Uint8 axis;
  Uint8 padding1;
  Uint8 padding2;
  Uint8 padding3;
  Sint16 value;
  Uint16 padding4;
};
typedef struct SDL_ControllerAxisEvent SDL_ControllerAxisEvent;
struct SDL_ControllerButtonEvent {
  Uint32 type;
  Uint32 timestamp;
  SDL_JoystickID which;
  Uint8 button;
  Uint8 state;
  Uint8 padding1;
  Uint8 padding2;
};
typedef struct SDL_ControllerButtonEvent SDL_ControllerButtonEvent;
struct SDL_ControllerDeviceEvent {
  Uint32 type;
  Uint32 timestamp;
  Sint32 which;
};
typedef struct SDL_ControllerDeviceEvent SDL_ControllerDeviceEvent;
struct SDL_ControllerTouchpadEvent {
  Uint32 type;
  Uint32 timestamp;
  SDL_JoystickID which;
  Sint32 touchpad;
  Sint32 finger;
  float x;
  float y;
  float pressure;
};
typedef struct SDL_ControllerTouchpadEvent SDL_ControllerTouchpadEvent;
struct SDL_ControllerSensorEvent {
  Uint32 type;
  Uint32 timestamp;
  SDL_JoystickID which;
  Sint32 sensor;
  float data[3];
  Uint64 timestamp_us;
};
typedef struct SDL_ControllerSensorEvent SDL_ControllerSensorEvent;
struct SDL_AudioDeviceEvent {
  Uint32 type;
  Uint32 timestamp;
  Uint32 which;
  Uint8 iscapture;
  Uint8 padding1;
  Uint8 padding2;
  Uint8 padding3;
};
typedef struct SDL_AudioDeviceEvent SDL_AudioDeviceEvent;
struct SDL_SensorEvent {
  Uint32 type;
  Uint32 timestamp;
  Sint32 which;
  float data[6];
  Uint64 timestamp_us;
};
typedef struct SDL_SensorEvent SDL_SensorEvent;
struct SDL_QuitEvent {
  Uint32 type;
  Uint32 timestamp;
};
typedef struct SDL_QuitEvent SDL_QuitEvent;
struct SDL_UserEvent {
  Uint32 type;
  Uint32 timestamp;
  Uint32 windowID;
  Sint32 code;
  void *data1;
  void *data2;
};
typedef struct SDL_UserEvent SDL_UserEvent;
typedef struct {
  Uint32 format;
  int w;
  int h;
  int refresh_rate;
  void *driverdata;
} SDL_DisplayMode;
struct SDL_SysWMEvent {
  Uint32 type;
  Uint32 timestamp;
  struct SDL_SysWMmsg *msg;
};
typedef struct SDL_SysWMEvent SDL_SysWMEvent;
struct SDL_TouchFingerEvent {
  Uint32 type;
  Uint32 timestamp;
  SDL_TouchID touchId;
  SDL_FingerID fingerId;
  float x;
  float y;
  float dx;
  float dy;
  float pressure;
  Uint32 windowID;
};
typedef struct SDL_TouchFingerEvent SDL_TouchFingerEvent;
struct SDL_MultiGestureEvent {
  Uint32 type;
  Uint32 timestamp;
  SDL_TouchID touchId;
  float dTheta;
  float dDist;
  float x;
  float y;
  Uint16 numFingers;
  Uint16 padding;
};
typedef struct SDL_MultiGestureEvent SDL_MultiGestureEvent;
struct SDL_DollarGestureEvent {
  Uint32 type;
  Uint32 timestamp;
  SDL_TouchID touchId;
  SDL_GestureID gestureId;
  Uint32 numFingers;
  float error;
  float x;
  float y;
};
typedef struct SDL_DollarGestureEvent SDL_DollarGestureEvent;
struct SDL_DropEvent {
  Uint32 type;
  Uint32 timestamp;
  char *file;
  Uint32 windowID;
};
typedef struct SDL_DropEvent SDL_DropEvent;
union SDL_Event {
  Uint32 type;
  SDL_CommonEvent common;
  SDL_DisplayEvent display;
  SDL_WindowEvent window;
  SDL_KeyboardEvent key;
  SDL_TextEditingEvent edit;
  SDL_TextEditingExtEvent editExt;
  SDL_TextInputEvent text;
  SDL_MouseMotionEvent motion;
  SDL_MouseButtonEvent button;
  SDL_MouseWheelEvent wheel;
  SDL_JoyAxisEvent jaxis;
  SDL_JoyBallEvent jball;
  SDL_JoyHatEvent jhat;
  SDL_JoyButtonEvent jbutton;
  SDL_JoyDeviceEvent jdevice;
  SDL_JoyBatteryEvent jbattery;
  SDL_ControllerAxisEvent caxis;
  SDL_ControllerButtonEvent cbutton;
  SDL_ControllerDeviceEvent cdevice;
  SDL_ControllerTouchpadEvent ctouchpad;
  SDL_ControllerSensorEvent csensor;
  SDL_AudioDeviceEvent adevice;
  SDL_SensorEvent sensor;
  SDL_QuitEvent quit;
  SDL_UserEvent user;
  SDL_SysWMEvent syswm;
  SDL_TouchFingerEvent tfinger;
  SDL_MultiGestureEvent mgesture;
  SDL_DollarGestureEvent dgesture;
  SDL_DropEvent drop;
  Uint8 padding[56];
};
struct SDL_Rect {
  int x;
  int y;
  int w;
  int h;
};
typedef struct SDL_Rect SDL_Rect;
struct SDL_Window;
typedef struct SDL_Window SDL_Window;
struct SDL_Renderer;
typedef struct SDL_Renderer SDL_Renderer;
struct SDL_RendererInfo {
  const char *name;
  Uint32 flags;
  Uint32 num_texture_formats;
  Uint32 texture_formats[16];
  int max_texture_width;
  int max_texture_height;
};
typedef struct SDL_RendererInfo SDL_RendererInfo;
struct SDL_Texture;
typedef struct SDL_Texture SDL_Texture;
struct SDL_Color {
  Uint8 r;
  Uint8 g;
  Uint8 b;
  Uint8 a;
};
typedef struct SDL_Color SDL_Color;
struct SDL_Palette {
  int ncolors;
  SDL_Color *colors;
  Uint32 version;
  int refcount;
};
typedef struct SDL_Palette SDL_Palette;
typedef struct SDL_PixelFormat SDL_PixelFormat;
struct SDL_PixelFormat {
  Uint32 format;
  SDL_Palette *palette;
  Uint8 BitsPerPixel;
  Uint8 BytesPerPixel;
  Uint8 padding[2];
  Uint32 Rmask;
  Uint32 Gmask;
  Uint32 Bmask;
  Uint32 Amask;
  Uint8 Rloss;
  Uint8 Gloss;
  Uint8 Bloss;
  Uint8 Aloss;
  Uint8 Rshift;
  Uint8 Gshift;
  Uint8 Bshift;
  Uint8 Ashift;
  int refcount;
  struct SDL_PixelFormat *next;
};
struct SDL_BlitMap;
typedef struct SDL_BlitMap SDL_BlitMap;
struct SDL_Surface {
  Uint32 flags;
  SDL_PixelFormat *format;
  int w;
  int h;
  int pitch;
  void *pixels;
  void *userdata;
  int locked;
  void *list_blitmap;
  SDL_Rect clip_rect;
  SDL_BlitMap *map;
  int refcount;
};
typedef struct SDL_Surface SDL_Surface;
int SDL_Init(Uint32) __attribute__((visibility("default")));
Uint32 SDL_WasInit(Uint32) __attribute__((visibility("default")));
void SDL_SetMainReady(void) __attribute__((visibility("default")));
void SDL_Quit(void) __attribute__((visibility("default")));
int SDL_WaitEvent(union SDL_Event *) __attribute__((visibility("default")));
int SDL_WaitEventTimeout(union SDL_Event *, int) __attribute__((visibility("default")));
int SDL_PollEvent(union SDL_Event *) __attribute__((visibility("default")));
Uint32 SDL_GetTicks(void) __attribute__((visibility("default")));
void SDL_Delay(Uint32) __attribute__((visibility("default")));
int SDL_GetCurrentDisplayMode(int, SDL_DisplayMode *) __attribute__((visibility("default")));
void SDL_EnableScreenSaver(void) __attribute__((visibility("default")));
SDL_Window *SDL_CreateWindow(const char *, int, int, int, int, Uint32) __attribute__((visibility("default")));
void SDL_GetWindowSize(SDL_Window *, int *, int *) __attribute__((visibility("default")));
SDL_Renderer *SDL_CreateRenderer(SDL_Window *, int, Uint32) __attribute__((visibility("default")));
void SDL_DestroyRenderer(SDL_Renderer *) __attribute__((visibility("default")));
int SDL_CreateWindowAndRenderer(int, int, Uint32, SDL_Window **, SDL_Renderer **) __attribute__((visibility("default")));
int SDL_GetRendererInfo(SDL_Renderer *, SDL_RendererInfo *) __attribute__((visibility("default")));
int SDL_GetRendererOutputSize(SDL_Renderer *, int *, int *) __attribute__((visibility("default")));
int SDL_SetRenderDrawColor(SDL_Renderer *, Uint8, Uint8, Uint8, Uint8) __attribute__((visibility("default")));
int SDL_RenderClear(SDL_Renderer *) __attribute__((visibility("default")));
void SDL_RenderPresent(SDL_Renderer *) __attribute__((visibility("default")));
int SDL_RenderCopy(SDL_Renderer *, SDL_Texture *, const SDL_Rect *, const SDL_Rect *) __attribute__((visibility("default")));
SDL_Texture *SDL_CreateTexture(SDL_Renderer *, Uint32, int, int, int) __attribute__((visibility("default")));
int SDL_UpdateTexture(SDL_Texture *, const SDL_Rect *, const void *, int) __attribute__((visibility("default")));
void SDL_DestroyTexture(SDL_Texture *) __attribute__((visibility("default")));
void SDL_SetWindowTitle(SDL_Window *, const char *) __attribute__((visibility("default")));
void SDL_GetWindowPosition(SDL_Window * window, int *x, int *y) __attribute__((visibility("default")));
void SDL_SetWindowPosition(SDL_Window * window, int x, int y) __attribute__((visibility("default")));
typedef int (*SDL_blit)(struct SDL_Surface *, SDL_Rect *, struct SDL_Surface *, SDL_Rect *);
SDL_Surface *SDL_CreateRGBSurface(Uint32, int, int, int, Uint32, Uint32, Uint32, Uint32) __attribute__((visibility("default")));
SDL_Surface *SDL_CreateRGBSurfaceFrom(void *, int, int, int, int, Uint32, Uint32, Uint32, Uint32) __attribute__((visibility("default")));
SDL_Surface *SDL_CreateRGBSurfaceWithFormatFrom(void *, int, int, int, int, Uint32) __attribute__((visibility("default")));
void SDL_FreeSurface(SDL_Surface *) __attribute__((visibility("default")));
int SDL_SetSurfacePalette(SDL_Surface *, SDL_Palette *) __attribute__((visibility("default")));
int SDL_LockSurface(SDL_Surface *) __attribute__((visibility("default")));
void SDL_UnlockSurface(SDL_Surface *) __attribute__((visibility("default")));
void SDL_SetWindowIcon(SDL_Window *, SDL_Surface *) __attribute__((visibility("default")));
int SDL_SetWindowFullscreen(SDL_Window *, Uint32) __attribute__((visibility("default")));
char *SDL_GetBasePath(void) __attribute__((visibility("default")));
char *SDL_GetPrefPath(const char *, const char *) __attribute__((visibility("default")));
typedef enum {
  SDL_POWERSTATE_UNKNOWN = 0,
  SDL_POWERSTATE_ON_BATTERY = 1,
  SDL_POWERSTATE_NO_BATTERY = 2,
  SDL_POWERSTATE_CHARGING = 3,
  SDL_POWERSTATE_CHARGED = 4,
} SDL_PowerState;
SDL_PowerState SDL_GetPowerInfo(int *, int *) __attribute__((visibility("default")));
const char *SDL_GetPlatform(void) __attribute__((visibility("default")));
typedef enum {
  SDL_FALSE = 0,
  SDL_TRUE = 1,
} SDL_bool;
SDL_bool SDL_HasClipboardText(void) __attribute__((visibility("default")));
char *SDL_GetClipboardText(void) __attribute__((visibility("default")));
int SDL_SetClipboardText(const char *) __attribute__((visibility("default")));
const char *SDL_GetError(void) __attribute__((visibility("default")));
SDL_bool SDL_SetHint(const char *, const char *) __attribute__((visibility("default")));
int SDL_NumJoysticks(void) __attribute__((visibility("default")));
const char *SDL_JoystickNameForIndex(int) __attribute__((visibility("default")));
SDL_Joystick *SDL_JoystickOpen(int) __attribute__((visibility("default")));
const char *SDL_JoystickName(SDL_Joystick *) __attribute__((visibility("default")));
SDL_JoystickGUID SDL_JoystickGetDeviceGUID(int) __attribute__((visibility("default")));
SDL_JoystickGUID SDL_JoystickGetGUID(SDL_Joystick *) __attribute__((visibility("default")));
void SDL_JoystickGetGUIDString(SDL_JoystickGUID, char *, int) __attribute__((visibility("default")));
SDL_JoystickGUID SDL_JoystickGetGUIDFromString(const char *) __attribute__((visibility("default")));
SDL_bool SDL_JoystickGetAttached(SDL_Joystick *) __attribute__((visibility("default")));
SDL_JoystickID SDL_JoystickInstanceID(SDL_Joystick *) __attribute__((visibility("default")));
int SDL_JoystickNumAxes(SDL_Joystick *) __attribute__((visibility("default")));
int SDL_JoystickNumBalls(SDL_Joystick *) __attribute__((visibility("default")));
int SDL_JoystickNumHats(SDL_Joystick *) __attribute__((visibility("default")));
int SDL_JoystickNumButtons(SDL_Joystick *) __attribute__((visibility("default")));
void SDL_JoystickUpdate(void) __attribute__((visibility("default")));
int SDL_JoystickEventState(int) __attribute__((visibility("default")));
Sint16 SDL_JoystickGetAxis(SDL_Joystick *, int) __attribute__((visibility("default")));
Uint8 SDL_JoystickGetHat(SDL_Joystick *, int) __attribute__((visibility("default")));
int SDL_JoystickGetBall(SDL_Joystick *, int, int *, int *) __attribute__((visibility("default")));
Uint8 SDL_JoystickGetButton(SDL_Joystick *, int) __attribute__((visibility("default")));
void SDL_JoystickClose(SDL_Joystick *) __attribute__((visibility("default")));
struct _SDL_GameController;
typedef struct _SDL_GameController SDL_GameController;
typedef enum {
  SDL_CONTROLLER_BINDTYPE_NONE = 0,
  SDL_CONTROLLER_BINDTYPE_BUTTON = 1,
  SDL_CONTROLLER_BINDTYPE_AXIS = 2,
  SDL_CONTROLLER_BINDTYPE_HAT = 3,
} SDL_GameControllerBindType;
struct SDL_GameControllerButtonBind {
  SDL_GameControllerBindType bindType;
  union {
    int button;
    int axis;
    struct {
      int hat;
      int hat_mask;
    } hat;
  } value;
};
typedef struct SDL_GameControllerButtonBind SDL_GameControllerButtonBind;
int SDL_GameControllerAddMapping(const char *) __attribute__((visibility("default")));
char *SDL_GameControllerMappingForGUID(SDL_JoystickGUID) __attribute__((visibility("default")));
char *SDL_GameControllerMapping(SDL_GameController *) __attribute__((visibility("default")));
SDL_bool SDL_IsGameController(int) __attribute__((visibility("default")));
const char *SDL_GameControllerNameForIndex(int) __attribute__((visibility("default")));
SDL_GameController *SDL_GameControllerOpen(int) __attribute__((visibility("default")));
const char *SDL_GameControllerName(SDL_GameController *) __attribute__((visibility("default")));
SDL_bool SDL_GameControllerGetAttached(SDL_GameController *) __attribute__((visibility("default")));
SDL_Joystick *SDL_GameControllerGetJoystick(SDL_GameController *) __attribute__((visibility("default")));
int SDL_GameControllerEventState(int) __attribute__((visibility("default")));
void SDL_GameControllerUpdate(void) __attribute__((visibility("default")));
int SDL_GameControllerRumble(SDL_GameController *, Uint16, Uint16, Uint32) __attribute__((visibility("default")));
typedef enum {
  SDL_CONTROLLER_AXIS_INVALID = -1,
  SDL_CONTROLLER_AXIS_LEFTX = 0,
  SDL_CONTROLLER_AXIS_LEFTY = 1,
  SDL_CONTROLLER_AXIS_RIGHTX = 2,
  SDL_CONTROLLER_AXIS_RIGHTY = 3,
  SDL_CONTROLLER_AXIS_TRIGGERLEFT = 4,
  SDL_CONTROLLER_AXIS_TRIGGERRIGHT = 5,
  SDL_CONTROLLER_AXIS_MAX = 6,
} SDL_GameControllerAxis;
SDL_GameControllerAxis SDL_GameControllerGetAxisFromString(const char *) __attribute__((visibility("default")));
const char *SDL_GameControllerGetStringForAxis(SDL_GameControllerAxis) __attribute__((visibility("default")));
SDL_GameControllerButtonBind SDL_GameControllerGetBindForAxis(SDL_GameController *, SDL_GameControllerAxis) __attribute__((visibility("default")));
Sint16 SDL_GameControllerGetAxis(SDL_GameController *, SDL_GameControllerAxis) __attribute__((visibility("default")));
typedef enum {
  SDL_CONTROLLER_BUTTON_INVALID = -1,
  SDL_CONTROLLER_BUTTON_A = 0,
  SDL_CONTROLLER_BUTTON_B = 1,
  SDL_CONTROLLER_BUTTON_X = 2,
  SDL_CONTROLLER_BUTTON_Y = 3,
  SDL_CONTROLLER_BUTTON_BACK = 4,
  SDL_CONTROLLER_BUTTON_GUIDE = 5,
  SDL_CONTROLLER_BUTTON_START = 6,
  SDL_CONTROLLER_BUTTON_LEFTSTICK = 7,
  SDL_CONTROLLER_BUTTON_RIGHTSTICK = 8,
  SDL_CONTROLLER_BUTTON_LEFTSHOULDER = 9,
  SDL_CONTROLLER_BUTTON_RIGHTSHOULDER = 10,
  SDL_CONTROLLER_BUTTON_DPAD_UP = 11,
  SDL_CONTROLLER_BUTTON_DPAD_DOWN = 12,
  SDL_CONTROLLER_BUTTON_DPAD_LEFT = 13,
  SDL_CONTROLLER_BUTTON_DPAD_RIGHT = 14,
  SDL_CONTROLLER_BUTTON_MISC1 = 15,
  SDL_CONTROLLER_BUTTON_PADDLE1 = 16,
  SDL_CONTROLLER_BUTTON_PADDLE2 = 17,
  SDL_CONTROLLER_BUTTON_PADDLE3 = 18,
  SDL_CONTROLLER_BUTTON_PADDLE4 = 19,
  SDL_CONTROLLER_BUTTON_TOUCHPAD = 20,
  SDL_CONTROLLER_BUTTON_MAX = 21,
} SDL_GameControllerButton;
SDL_GameControllerButton SDL_GameControllerGetButtonFromString(const char *) __attribute__((visibility("default")));
const char *SDL_GameControllerGetStringForButton(SDL_GameControllerButton) __attribute__((visibility("default")));
SDL_GameControllerButtonBind SDL_GameControllerGetBindForButton(SDL_GameController *, SDL_GameControllerButton) __attribute__((visibility("default")));
Uint8 SDL_GameControllerGetButton(SDL_GameController *, SDL_GameControllerButton) __attribute__((visibility("default")));
void SDL_GameControllerClose(SDL_GameController *) __attribute__((visibility("default")));
static const int SDL_HAT_CENTERED = 0;
static const int SDL_HAT_UP = 1;
static const int SDL_HAT_RIGHT = 2;
static const int SDL_HAT_DOWN = 4;
static const int SDL_HAT_LEFT = 8;
static const int SDL_HAT_RIGHTUP = 3;
static const int SDL_HAT_RIGHTDOWN = 6;
static const int SDL_HAT_LEFTUP = 9;
static const int SDL_HAT_LEFTDOWN = 12;
int SDL_GetNumTouchDevices(void) __attribute__((visibility("default")));
SDL_TouchID SDL_GetTouchDevice(int) __attribute__((visibility("default")));
int SDL_GetNumTouchFingers(SDL_TouchID) __attribute__((visibility("default")));
SDL_Finger *SDL_GetTouchFinger(SDL_TouchID, int) __attribute__((visibility("default")));
static const int SDL_INIT_TIMER = 1;
static const int SDL_INIT_AUDIO = 16;
static const int SDL_INIT_VIDEO = 32;
static const int SDL_INIT_JOYSTICK = 512;
static const int SDL_INIT_HAPTIC = 4096;
static const int SDL_INIT_GAMECONTROLLER = 8192;
static const int SDL_INIT_EVENTS = 16384;
static const int SDL_INIT_NOPARACHUTE = 1048576;
static const int SDL_INIT_EVERYTHING = 62001;
static const int SDL_WINDOWPOS_UNDEFINED = 536805376;
static const int SDL_WINDOW_FULLSCREEN = 1;
static const int SDL_WINDOW_RESIZABLE = 32;
static const int SDL_WINDOW_FULLSCREEN_DESKTOP = 4097;
static const int SDL_WINDOW_ALLOW_HIGHDPI = 8192;
typedef enum {
  SDL_TEXTUREACCESS_STATIC = 0,
  SDL_TEXTUREACCESS_STREAMING = 1,
  SDL_TEXTUREACCESS_TARGET = 2,
} SDL_TextureAccess;
static const int SDL_PIXELFORMAT_ARGB8888 = 372645892;
static const int SDL_PIXELFORMAT_RGBA8888 = 373694468;
static const int SDL_PIXELFORMAT_ABGR8888 = 376840196;
static const int SDL_PIXELFORMAT_BGRA8888 = 377888772;
static const int SDL_PIXELFORMAT_RGBA32 = 376840196;
static const int SDL_PIXELFORMAT_ARGB32 = 377888772;
static const int SDL_PIXELFORMAT_BGRA32 = 372645892;
static const int SDL_PIXELFORMAT_ABGR32 = 373694468;
struct SDL_version {
  Uint8 major;
  Uint8 minor;
  Uint8 patch;
};
void SDL_GetVersion(struct SDL_version *) __attribute__((visibility("default")));
void SDL_free(void *) __attribute__((visibility("default")));
]]
