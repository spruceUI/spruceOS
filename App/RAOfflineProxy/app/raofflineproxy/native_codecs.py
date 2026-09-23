from __future__ import annotations

"""ctypes bindings to system libzstd / libcrypto.

ROCKNIX has no pip (no ``zstandard``/``cryptography`` packages), but both
libzstd and OpenSSL's libcrypto ship as system shared libraries, so we bind
directly instead of vendoring wheels. Used by :mod:`rvz_datasource` to
decompress RVZ groups and re-encrypt Wii partition data for hashing.
"""

import ctypes
import ctypes.util


class CodecError(Exception):
    pass


def _load(names: tuple[str, ...], sonames: tuple[str, ...]) -> ctypes.CDLL:
    for name in names:
        try:
            return ctypes.CDLL(name)
        except OSError:
            continue
    for soname in sonames:
        found = ctypes.util.find_library(soname)
        if found:
            try:
                return ctypes.CDLL(found)
            except OSError:
                continue
    raise CodecError(f"could not load any of {names}")


_ZSTD_CONTENTSIZE_UNKNOWN = ctypes.c_ulonglong(-1).value
_ZSTD_CONTENTSIZE_ERROR = ctypes.c_ulonglong(-2).value

_zstd_cache: ctypes.CDLL | None = None
_crypto_cache: ctypes.CDLL | None = None


def _zstd() -> ctypes.CDLL:
    """Loaded lazily: RVZ hashing is GameCube/Wii-only, so platforms without
    Dolphin support (e.g. Onion) must not fail to import rvz_datasource just
    because they lack libzstd."""
    global _zstd_cache
    if _zstd_cache is not None:
        return _zstd_cache

    lib = _load(("libzstd.so.1", "libzstd.so", "libzstd.dylib"), ("zstd",))
    lib.ZSTD_decompress.argtypes = [
        ctypes.c_void_p,
        ctypes.c_size_t,
        ctypes.c_void_p,
        ctypes.c_size_t,
    ]
    lib.ZSTD_decompress.restype = ctypes.c_size_t
    lib.ZSTD_isError.argtypes = [ctypes.c_size_t]
    lib.ZSTD_isError.restype = ctypes.c_uint
    lib.ZSTD_getFrameContentSize.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    lib.ZSTD_getFrameContentSize.restype = ctypes.c_ulonglong
    _zstd_cache = lib
    return lib


def zstd_decompress(encoded: bytes, expected_size: int) -> bytes:
    zstd = _zstd()
    dest = ctypes.create_string_buffer(expected_size)
    decoded_size = zstd.ZSTD_decompress(dest, expected_size, encoded, len(encoded))
    if zstd.ZSTD_isError(decoded_size):
        raise CodecError("zstd decompress failed")
    if decoded_size != expected_size:
        raise CodecError(
            f"zstd decompress produced unexpected size={decoded_size} expected={expected_size}"
        )
    return dest.raw[:decoded_size]


def zstd_frame_content_size(encoded: bytes) -> int:
    zstd = _zstd()
    size = zstd.ZSTD_getFrameContentSize(encoded, len(encoded))
    if size in (_ZSTD_CONTENTSIZE_UNKNOWN, _ZSTD_CONTENTSIZE_ERROR):
        raise CodecError("zstd frame content size unavailable")
    return size


def _crypto() -> ctypes.CDLL:
    """Loaded lazily; see _zstd() for why."""
    global _crypto_cache
    if _crypto_cache is not None:
        return _crypto_cache

    lib = _load(("libcrypto.so.3", "libcrypto.so", "libcrypto.dylib"), ("crypto",))
    lib.EVP_CIPHER_CTX_new.restype = ctypes.c_void_p
    lib.EVP_aes_128_cbc.restype = ctypes.c_void_p
    lib.EVP_EncryptInit_ex.argtypes = [
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_char_p,
    ]
    lib.EVP_EncryptInit_ex.restype = ctypes.c_int
    lib.EVP_CIPHER_CTX_set_padding.argtypes = [ctypes.c_void_p, ctypes.c_int]
    lib.EVP_EncryptUpdate.argtypes = [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.POINTER(ctypes.c_int),
        ctypes.c_char_p,
        ctypes.c_int,
    ]
    lib.EVP_EncryptUpdate.restype = ctypes.c_int
    lib.EVP_EncryptFinal_ex.argtypes = [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.POINTER(ctypes.c_int),
    ]
    lib.EVP_EncryptFinal_ex.restype = ctypes.c_int
    lib.EVP_CIPHER_CTX_free.argtypes = [ctypes.c_void_p]
    _crypto_cache = lib
    return lib


def aes_128_cbc_encrypt(key: bytes, iv: bytes, data: bytes) -> bytes:
    """AES/CBC/NoPadding encrypt, matching javax.crypto's Cipher.ENCRYPT_MODE
    usage in the Android port (used to rebuild the on-disc encrypted Wii
    hash-tree/data layout from RVZ's decrypted storage, not for confidentiality)."""
    if len(key) != 16 or len(iv) != 16:
        raise CodecError("AES-128-CBC requires 16-byte key and IV")
    if len(data) % 16 != 0:
        raise CodecError("AES-128-CBC/NoPadding requires block-aligned input")

    crypto = _crypto()
    ctx = crypto.EVP_CIPHER_CTX_new()
    if not ctx:
        raise CodecError("EVP_CIPHER_CTX_new failed")
    try:
        cipher = crypto.EVP_aes_128_cbc()
        if crypto.EVP_EncryptInit_ex(ctx, cipher, None, key, iv) != 1:
            raise CodecError("EVP_EncryptInit_ex failed")
        crypto.EVP_CIPHER_CTX_set_padding(ctx, 0)

        out = ctypes.create_string_buffer(len(data) + 16)
        out_len = ctypes.c_int(0)
        if crypto.EVP_EncryptUpdate(ctx, out, ctypes.byref(out_len), data, len(data)) != 1:
            raise CodecError("EVP_EncryptUpdate failed")
        total = out_len.value

        final_len = ctypes.c_int(0)
        final_buf = ctypes.create_string_buffer(16)
        if crypto.EVP_EncryptFinal_ex(ctx, final_buf, ctypes.byref(final_len)) != 1:
            raise CodecError("EVP_EncryptFinal_ex failed")
        total += final_len.value

        return out.raw[:out_len.value] + final_buf.raw[:final_len.value]
    finally:
        crypto.EVP_CIPHER_CTX_free(ctx)
