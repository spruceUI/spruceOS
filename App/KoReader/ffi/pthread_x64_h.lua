local ffi = require("ffi")

ffi.cdef[[
typedef long unsigned int pthread_t;
typedef union {
  char __size[56];
  long int __align;
} pthread_attr_t;
int pthread_attr_init(pthread_attr_t *) __attribute__((__nothrow__, __leaf__));
int pthread_attr_setdetachstate(pthread_attr_t *, int) __attribute__((__nothrow__, __leaf__));
int pthread_attr_destroy(pthread_attr_t *) __attribute__((__nothrow__, __leaf__));
static const int PTHREAD_CREATE_DETACHED = 1;
int pthread_create(pthread_t *restrict, const pthread_attr_t *restrict, void *(*)(void *), void *restrict) __attribute__((__nothrow__));
]]
