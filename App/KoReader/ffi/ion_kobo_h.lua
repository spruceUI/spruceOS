local ffi = require("ffi")

ffi.cdef[[
typedef int ion_user_handle_t;
struct ion_allocation_data {
  size_t len;
  size_t align;
  unsigned int heap_id_mask;
  unsigned int flags;
  ion_user_handle_t handle;
};
struct ion_fd_data {
  ion_user_handle_t handle;
  int fd;
};
struct ion_handle_data {
  ion_user_handle_t handle;
};
static const int ION_IOC_ALLOC = 3222554880;
static const int ION_IOC_FREE = 3221506305;
static const int ION_IOC_MAP = 3221768450;
enum ion_heap_mask {
  ION_HEAP_MASK_SYSTEM = 1,
  ION_HEAP_MASK_SYSTEM_CONTIG = 2,
  ION_HEAP_MASK_CARVEOUT = 4,
  ION_HEAP_MASK_CHUNK = 8,
  ION_HEAP_MASK_DMA = 16,
  ION_HEAP_MASK_CUSTOM = 32,
  ION_HEAP_MASK_SECURE = 64,
};
]]
