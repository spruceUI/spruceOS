// LD_PRELOAD fix for the Smart Pro S Vulkan memory leak: TrimUI's panel_dsi_get_modes (fw 1.0.2) orphans one
// drm_display_mode per connector probe, and libmali's VK_KHR_display presenter calls drmModeGetConnector (a full
// probe) twice per frame, about 200 MB of kernel memory an hour. This probes each connector at most once per
// DRM_NOPROBE_INTERVAL seconds (default 1; 0 = never again; negative = pass every call through) and hands back
// private copies. DRM_NOPROBE_DEBUG=1 logs its decisions to /dev/kmsg. Loaded via VK_DISPLAY_PRELOAD (SmartProS.cfg).
// Build (Arm GNU Toolchain 10.3 aarch64, glibc 2.17 floor):
//   aarch64-none-linux-gnu-gcc -O2 -Wall -Wextra -fPIC -shared -o libdrm_noprobe.so drm_noprobe.c -ldl -lpthread
//   aarch64-none-linux-gnu-strip libdrm_noprobe.so
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* libdrm's public, ABI-stable layout (xf86drmMode.h) */
typedef struct {
    uint32_t clock;
    uint16_t hdisplay, hsync_start, hsync_end, htotal, hskew;
    uint16_t vdisplay, vsync_start, vsync_end, vtotal, vscan;
    uint32_t vrefresh, flags, type;
    char name[32];
} mode_info;

typedef struct {
    uint32_t connector_id, encoder_id, connector_type, connector_type_id;
    int connection;
    uint32_t mmWidth, mmHeight;
    int subpixel;
    int count_modes;
    mode_info *modes;
    int count_props;
    uint32_t *props;
    uint64_t *prop_values;
    int count_encoders;
    uint32_t *encoders;
} connector;

typedef connector *(*get_connector_fn)(int fd, uint32_t connector_id);

#define DEFAULT_INTERVAL 1
#define MAX_CONNECTORS 16
#define LOG_FIRST 64

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static get_connector_fn real_get;
static struct { uint32_t id; connector *copy; time_t when; } cache[MAX_CONNECTORS];
static int ncache, configured, debug, kmsg_fd = -2;
static long interval;
static unsigned long n_probe, n_cached;

static void klog(const char *fmt, ...)
    __attribute__((format(printf, 1, 2)));

static void klog(const char *fmt, ...)
{
    char buf[200];
    va_list ap;
    int n;

    if (!debug)
        return;
    if (kmsg_fd == -2)
        kmsg_fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (kmsg_fd < 0)
        return;
    n = snprintf(buf, sizeof(buf), "drm_noprobe[%d]: ", (int)getpid());
    va_start(ap, fmt);
    n += vsnprintf(buf + n, sizeof(buf) - n, fmt, ap);
    va_end(ap);
    if (write(kmsg_fd, buf, n > (int)sizeof(buf) ? (int)sizeof(buf) : n) < 0)
        kmsg_fd = -1;
}

/* Called with the lock held, on the first drmModeGetConnector call. */
static void configure(void)
{
    const char *e = getenv("DRM_NOPROBE_INTERVAL");
    const char *d = getenv("DRM_NOPROBE_DEBUG");

    real_get = (get_connector_fn)dlsym(RTLD_NEXT, "drmModeGetConnector");
    interval = e ? atol(e) : DEFAULT_INTERVAL;
    debug = d && *d && strcmp(d, "0") != 0;
    configured = 1;
}

static void *dup_mem(const void *src, size_t n)
{
    void *p;

    if (!src || !n)
        return NULL;
    p = malloc(n);
    if (p)
        memcpy(p, src, n);
    return p;
}

/* Allocated with malloc so libdrm's drmModeFreeConnector (drmFree = free) can release it. */
static connector *dup_connector(const connector *s)
{
    connector *d = malloc(sizeof(*d));

    if (!d)
        return NULL;
    *d = *s;
    d->modes = dup_mem(s->modes, (size_t)s->count_modes * sizeof(*s->modes));
    d->props = dup_mem(s->props, (size_t)s->count_props * sizeof(*s->props));
    d->prop_values = dup_mem(s->prop_values, (size_t)s->count_props * sizeof(*s->prop_values));
    d->encoders = dup_mem(s->encoders, (size_t)s->count_encoders * sizeof(*s->encoders));
    return d;
}

static void free_connector(connector *c)
{
    if (!c)
        return;
    free(c->modes);
    free(c->props);
    free(c->prop_values);
    free(c->encoders);
    free(c);
}

connector *drmModeGetConnector(int fd, uint32_t connector_id)
{
    connector *r = NULL, *fresh;
    time_t now = time(NULL);
    int i, slot = -1;
    unsigned long total;

    pthread_mutex_lock(&lock);
    if (!configured)
        configure();
    for (i = 0; i < ncache; i++)
        if (cache[i].id == connector_id)
            slot = i;
    if (slot >= 0 && cache[slot].copy && interval >= 0 && (interval == 0 || now - cache[slot].when < interval)) {
        r = dup_connector(cache[slot].copy);
        n_cached++;
    }
    total = n_probe + n_cached;
    pthread_mutex_unlock(&lock);

    if (r) {
        if (total <= LOG_FIRST || total % 600 == 0)
            klog("call %lu id=%u cached conn=%d modes=%d\n", total, connector_id,
                 r->connection, r->count_modes);
        return r;
    }

    r = real_get ? real_get(fd, connector_id) : NULL;
    fresh = r ? dup_connector(r) : NULL;
    pthread_mutex_lock(&lock);
    n_probe++;
    if (fresh) {
        if (slot < 0 && ncache < MAX_CONNECTORS)
            slot = ncache++;
        if (slot >= 0) {
            free_connector(cache[slot].copy);
            cache[slot].id = connector_id;
            cache[slot].copy = fresh;
            cache[slot].when = now;
        } else {
            free_connector(fresh);
        }
    }
    total = n_probe + n_cached;
    pthread_mutex_unlock(&lock);
    if (total <= LOG_FIRST || total % 600 == 0)
        klog("call %lu id=%u probed conn=%d modes=%d\n", total, connector_id,
             r ? r->connection : -1, r ? r->count_modes : -1);
    return r;
}

/* Only processes that called it report: a launch chain inherits LD_PRELOAD. */
__attribute__((destructor)) static void report(void)
{
    if (n_probe || n_cached)
        klog("exit probes=%lu cached=%lu connectors=%d\n", n_probe, n_cached, ncache);
}
