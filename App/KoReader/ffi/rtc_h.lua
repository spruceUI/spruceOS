local ffi = require("ffi")

ffi.cdef[[
struct rtc_time {
  int tm_sec;
  int tm_min;
  int tm_hour;
  int tm_mday;
  int tm_mon;
  int tm_year;
  int tm_wday;
  int tm_yday;
  int tm_isdst;
};
struct rtc_wkalrm {
  unsigned char enabled;
  unsigned char pending;
  struct rtc_time time;
};
static const int RTC_AIE_ON = 28673;
static const int RTC_AIE_OFF = 28674;
static const int RTC_WKALM_SET = 1076391951;
static const int RTC_WKALM_RD = 2150133776;
static const int RTC_RD_TIME = 2149871625;
typedef long int time_t;
struct tm {
  int tm_sec;
  int tm_min;
  int tm_hour;
  int tm_mday;
  int tm_mon;
  int tm_year;
  int tm_wday;
  int tm_yday;
  int tm_isdst;
  long int tm_gmtoff;
  const char *tm_zone;
};
time_t time(time_t *) __attribute__((nothrow, leaf));
struct tm *gmtime(const time_t *) __attribute__((nothrow, leaf));
struct tm *gmtime_r(const time_t *restrict, struct tm *restrict) __attribute__((nothrow, leaf));
struct tm *localtime(const time_t *) __attribute__((nothrow, leaf));
struct tm *localtime_r(const time_t *restrict, struct tm *restrict) __attribute__((nothrow, leaf));
time_t timegm(struct tm *) __attribute__((nothrow, leaf));
time_t mktime(struct tm *) __attribute__((nothrow, leaf));
int settimeofday(const struct timeval *, const struct timezone *) __attribute__((nothrow, leaf));
void tzset(void) __attribute__((nothrow, leaf));
]]
