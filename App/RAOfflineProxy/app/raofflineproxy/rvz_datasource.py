"""Random-access reader for Dolphin's RVZ GameCube/Wii disc container.

Port of the Android app's ``RvzRomDataSource.kt`` (WIA/RVZ header parsing,
zstd group decompression, Wii AES partition decryption, hash-tree
reconstruction) to Python, so ROCKNIX's Smart Cache can hash ``.rvz`` files
through the same shared native hasher (``raproxy_hash_disc_datasource``) that
already handles CHD. See ``third_party/rcheevos_glue/rchash_glue.h`` for the
random-access callback contract this feeds.

Only RVZ is supported (not the older WIA format), matching the Android port.
"""

from __future__ import annotations

import hashlib
import struct
from dataclasses import dataclass, field

from .native_codecs import CodecError, zstd_decompress, zstd_frame_content_size, aes_128_cbc_encrypt

RVZ_MAGIC = b"RVZ\x01"
_HEADER_1_SIZE = 0x48
_HEADER_2_MIN_SIZE = 0xD5
_DISC_TYPE_GAMECUBE = 1
_DISC_TYPE_WII = 2
_COMPRESSION_NONE = 0
_COMPRESSION_ZSTD = 5
_DISC_HEADER_SIZE = 0x80
_PARTITION_ENTRY_SIZE = 0x30
_PARTITION_DATA_ENTRY_SIZE = 0x10
_RAW_DATA_ENTRY_SIZE = 0x18
_GROUP_ENTRY_SIZE = 0x0C
_HASH_EXCEPTION_ENTRY_SIZE = 0x16
_GROUP_COMPRESSED_BIT = 0x8000_0000
_GROUP_SIZE_MASK = 0x7FFF_FFFF
_SECTOR_SIZE = 0x8000
_SEED_SIZE = 68
_HEADER_1_HASH_END = 0x34
_WII_CLUSTER_HEADER_SIZE = 0x400
_WII_CLUSTER_DATA_SIZE = 0x7C00
_WII_CLUSTER_TOTAL_SIZE = _WII_CLUSTER_HEADER_SIZE + _WII_CLUSTER_DATA_SIZE
_WII_GROUP_BLOCK_COUNT = 64
_WII_GROUP_DATA_SIZE = _WII_CLUSTER_DATA_SIZE * _WII_GROUP_BLOCK_COUNT
_WII_GROUP_TOTAL_SIZE = _WII_CLUSTER_TOTAL_SIZE * _WII_GROUP_BLOCK_COUNT
_WII_HASH_HEADER_IV_OFFSET = 0x3D0
_PARTITION_COUNT_OFFSET = 0x90
_PARTITION_ENTRY_SIZE_OFFSET = 0x94
_PARTITION_OFFSET_OFFSET = 0x98
_PARTITION_HASH_OFFSET = 0xA0
_RAW_ENTRY_COUNT_OFFSET = 0xB4
_RAW_ENTRY_OFFSET_OFFSET = 0xB8
_RAW_ENTRY_SIZE_OFFSET = 0xC0
_GROUP_ENTRY_COUNT_OFFSET = 0xC4
_GROUP_ENTRY_OFFSET_OFFSET = 0xC8
_GROUP_ENTRY_SIZE_OFFSET = 0xD0
_ZERO_IV = bytes(16)
_MASK32 = 0xFFFF_FFFF


class RvzParseError(Exception):
    pass


class FileReadSource:
    """Minimal random-access reader over a plain file path, used as the
    ``delegate`` RVZ parses its own (still-compressed) container bytes from."""

    def __init__(self, path):
        self._file = open(path, "rb")

    def read(self, offset: int, length: int) -> bytes:
        self._file.seek(offset)
        return self._file.read(length)

    def close(self) -> None:
        self._file.close()


def _sha1(data: bytes) -> bytes:
    return hashlib.sha1(data).digest()


def _be_u16(data: bytes, offset: int) -> int:
    return struct.unpack_from(">H", data, offset)[0]


def _be_u32(data: bytes, offset: int) -> int:
    return struct.unpack_from(">I", data, offset)[0]


def _be_i32(data: bytes, offset: int) -> int:
    return struct.unpack_from(">i", data, offset)[0]


def _be_u64(data: bytes, offset: int) -> int:
    return struct.unpack_from(">Q", data, offset)[0]


def _align_to_4(value: int) -> int:
    return (value + 3) & ~3


@dataclass
class _WiiPartitionDataEntry:
    first_sector: int
    number_of_sectors: int
    group_index: int
    group_count: int


@dataclass
class _WiiPartition:
    key: bytes
    data_entries: list
    first_sector: int
    total_sectors: int
    group_cache: dict = field(default_factory=dict)

    @property
    def raw_data_offset(self) -> int:
        return self.first_sector * _SECTOR_SIZE

    @property
    def decrypted_size(self) -> int:
        return self.total_sectors * _WII_CLUSTER_DATA_SIZE


@dataclass
class _HashException:
    offset: int
    hash: bytes


@dataclass
class _PartitionGroup:
    main_data: bytes
    exception_lists: list


@dataclass
class _RawDataEntry:
    logical_start: int
    logical_end: int
    group_index: int
    group_count: int


@dataclass
class _GroupEntry:
    data_offset: int
    data_size: int
    packed_size: int

    @property
    def uses_file_compression(self) -> bool:
        return bool(self.data_size & _GROUP_COMPRESSED_BIT)


class RvzDataSource:
    """Random-access reader over a decompressed RVZ GameCube/Wii disc image."""

    def __init__(self, read_source, iso_file_size, disc_header, chunk_size,
                 file_compression_type, raw_entries, group_entries, wii_partitions):
        self._read_source = read_source
        self.length = iso_file_size
        self._disc_header = disc_header
        self._chunk_size = chunk_size
        self._file_compression_type = file_compression_type
        self._raw_entries = raw_entries
        self._group_entries = group_entries
        self._wii_partitions = wii_partitions
        self._raw_group_index = -1
        self._raw_group_data = None
        self._partition_group_index = -1
        self._partition_group = None

    @classmethod
    def open(cls, read_source) -> "RvzDataSource | None":
        try:
            return cls._parse(read_source)
        except Exception:
            return None

    @classmethod
    def _parse(cls, read_source) -> "RvzDataSource":
        header1 = _read_fully(read_source, 0, _HEADER_1_SIZE)
        if header1[0:4] != RVZ_MAGIC:
            raise RvzParseError("RVZ magic mismatch")

        header2_size = _be_u32(header1, 0x0C)
        if header2_size < _HEADER_2_MIN_SIZE:
            raise RvzParseError("RVZ header2 too small")
        iso_file_size = _be_u64(header1, 0x24)
        if iso_file_size < _DISC_HEADER_SIZE:
            raise RvzParseError("RVZ iso size too small")

        if _sha1(header1[0:_HEADER_1_HASH_END]) != header1[_HEADER_1_HASH_END:_HEADER_1_SIZE]:
            raise RvzParseError("RVZ header1 SHA-1 mismatch")

        header2 = _read_fully(read_source, _HEADER_1_SIZE, header2_size)
        if _sha1(header2) != header1[0x10:0x24]:
            raise RvzParseError("RVZ header2 SHA-1 mismatch")

        disc_type_raw = _be_u32(header2, 0x00)
        if disc_type_raw not in (_DISC_TYPE_GAMECUBE, _DISC_TYPE_WII):
            raise RvzParseError("Unsupported RVZ disc type")
        is_wii = disc_type_raw == _DISC_TYPE_WII

        compression_type = _be_u32(header2, 0x04)
        if compression_type not in (_COMPRESSION_NONE, _COMPRESSION_ZSTD):
            raise RvzParseError(f"Unsupported RVZ compression type={compression_type}")
        chunk_size = _be_u32(header2, 0x0C)
        if chunk_size <= 0:
            raise RvzParseError("Invalid RVZ chunk size")
        disc_header = header2[0x10:0x10 + _DISC_HEADER_SIZE]

        partition_entry_count = _be_u32(header2, _PARTITION_COUNT_OFFSET)
        partition_entry_size = _be_u32(header2, _PARTITION_ENTRY_SIZE_OFFSET)
        partition_entries_offset = _be_u64(header2, _PARTITION_OFFSET_OFFSET)
        partition_entries_hash = header2[_PARTITION_HASH_OFFSET:_PARTITION_HASH_OFFSET + 20]
        raw_entry_count = _be_u32(header2, _RAW_ENTRY_COUNT_OFFSET)
        raw_entries_offset = _be_u64(header2, _RAW_ENTRY_OFFSET_OFFSET)
        raw_entries_size = _be_u32(header2, _RAW_ENTRY_SIZE_OFFSET)
        group_entry_count = _be_u32(header2, _GROUP_ENTRY_COUNT_OFFSET)
        group_entries_offset = _be_u64(header2, _GROUP_ENTRY_OFFSET_OFFSET)
        group_entries_size = _be_u32(header2, _GROUP_ENTRY_SIZE_OFFSET)

        wii_partitions = []
        if is_wii and partition_entry_count > 0:
            partition_entries_bytes = _read_fully(
                read_source, partition_entries_offset, partition_entry_count * partition_entry_size
            )
            if _sha1(partition_entries_bytes) != partition_entries_hash:
                raise RvzParseError("RVZ partition entries SHA-1 mismatch")
            wii_partitions = _parse_partition_entries(
                partition_entries_bytes, partition_entry_count, partition_entry_size
            )

        raw_entries_bytes = _read_metadata_block(
            read_source, raw_entries_offset, raw_entries_size, compression_type,
            raw_entry_count * _RAW_DATA_ENTRY_SIZE,
        )
        group_entries_bytes = _read_metadata_block(
            read_source, group_entries_offset, group_entries_size, compression_type,
            group_entry_count * _GROUP_ENTRY_SIZE,
        )

        raw_entries = _parse_raw_entries(raw_entries_bytes, raw_entry_count)
        group_entries = _parse_group_entries(group_entries_bytes, group_entry_count)

        return cls(
            read_source=read_source,
            iso_file_size=iso_file_size,
            disc_header=disc_header,
            chunk_size=chunk_size,
            file_compression_type=compression_type,
            raw_entries=raw_entries,
            group_entries=group_entries,
            wii_partitions=wii_partitions,
        )

    def read(self, offset: int, length: int) -> bytes:
        if offset < 0 or length <= 0 or offset >= self.length:
            return b""
        remaining = self.length - offset
        target_length = min(length, remaining)

        out = bytearray()
        current_offset = offset

        if current_offset < _DISC_HEADER_SIZE:
            header_offset = current_offset
            header_count = min(target_length - len(out), _DISC_HEADER_SIZE - header_offset)
            out += self._disc_header[header_offset:header_offset + header_count]
            current_offset += header_count

        while len(out) < target_length:
            partition = self._find_wii_partition(current_offset)
            if partition is not None:
                chunk = self._read_wii_partition_bytes(
                    partition, current_offset, target_length - len(out)
                )
                if not chunk:
                    break
                out += chunk
                current_offset += len(chunk)
                continue

            entry = self._find_raw_entry(current_offset)
            if entry is None:
                break
            entry_offset = current_offset - entry.logical_start
            group_index = entry_offset // self._chunk_size
            if group_index >= entry.group_count:
                break

            group_logical_start = entry.logical_start + group_index * self._chunk_size
            group_logical_size = min(self._chunk_size, entry.logical_end - group_logical_start)
            group_data = self._read_group(entry.group_index + group_index, group_logical_size, group_logical_start)
            offset_in_group = current_offset - group_logical_start
            bytes_from_group = min(group_logical_size - offset_in_group, target_length - len(out))
            out += group_data[offset_in_group:offset_in_group + bytes_from_group]
            current_offset += bytes_from_group

        return bytes(out)

    def _find_wii_partition(self, offset: int):
        for partition in self._wii_partitions:
            start = partition.raw_data_offset
            end = start + partition.total_sectors * _SECTOR_SIZE
            if start <= offset < end:
                return partition
        return None

    def _find_raw_entry(self, offset: int):
        for entry in self._raw_entries:
            if entry.logical_start <= offset < entry.logical_end:
                return entry
        return None

    def _read_wii_partition_bytes(self, partition: _WiiPartition, offset: int, max_length: int) -> bytes:
        partition_end = partition.raw_data_offset + partition.total_sectors * _SECTOR_SIZE
        target_end = min(offset + max_length, partition_end)
        current_offset = offset
        out = bytearray()
        while current_offset < target_end:
            group_start = ((current_offset - partition.raw_data_offset) // _WII_GROUP_TOTAL_SIZE) * _WII_GROUP_DATA_SIZE
            encrypted_group = self._get_encrypted_wii_group(partition, group_start)
            if encrypted_group is None:
                break
            group_raw_start = partition.raw_data_offset + (group_start // _WII_CLUSTER_DATA_SIZE) * _SECTOR_SIZE
            offset_in_group = current_offset - group_raw_start
            bytes_from_group = min(len(encrypted_group) - offset_in_group, target_end - current_offset)
            out += encrypted_group[offset_in_group:offset_in_group + bytes_from_group]
            current_offset += bytes_from_group
        return bytes(out)

    def _get_encrypted_wii_group(self, partition: _WiiPartition, group_start: int):
        cached = partition.group_cache.get(group_start)
        if cached is not None:
            return cached

        decrypted_blocks = [bytearray(_WII_CLUSTER_DATA_SIZE) for _ in range(_WII_GROUP_BLOCK_COUNT)]
        for block_index in range(_WII_GROUP_BLOCK_COUNT):
            block_offset = group_start + block_index * _WII_CLUSTER_DATA_SIZE
            if block_offset >= partition.decrypted_size:
                continue
            if not self._read_wii_partition_decrypted(partition, block_offset, decrypted_blocks[block_index]):
                return None

        hash_blocks = _build_wii_hash_blocks(decrypted_blocks)
        _apply_wii_hash_exceptions(hash_blocks, self._collect_wii_hash_exceptions(partition, group_start))

        encrypted = bytearray(_WII_GROUP_TOTAL_SIZE)
        for block_index in range(_WII_GROUP_BLOCK_COUNT):
            header_bytes = bytes(hash_blocks[block_index])
            encrypted_header = aes_128_cbc_encrypt(partition.key, _ZERO_IV, header_bytes)
            data_iv = encrypted_header[_WII_HASH_HEADER_IV_OFFSET:_WII_HASH_HEADER_IV_OFFSET + 16]
            encrypted_data = aes_128_cbc_encrypt(partition.key, data_iv, bytes(decrypted_blocks[block_index]))
            output_offset = block_index * _WII_CLUSTER_TOTAL_SIZE
            encrypted[output_offset:output_offset + _WII_CLUSTER_HEADER_SIZE] = encrypted_header
            encrypted[output_offset + _WII_CLUSTER_HEADER_SIZE:output_offset + _WII_CLUSTER_TOTAL_SIZE] = encrypted_data

        result = bytes(encrypted)
        partition.group_cache[group_start] = result
        return result

    def _read_wii_partition_decrypted(self, partition: _WiiPartition, offset: int, destination: bytearray) -> bool:
        wii_chunk_size = self._chunk_size * _WII_CLUSTER_DATA_SIZE // _SECTOR_SIZE
        for entry in partition.data_entries:
            entry_offset = (entry.first_sector - partition.first_sector) * _WII_CLUSTER_DATA_SIZE
            entry_size = entry.number_of_sectors * _WII_CLUSTER_DATA_SIZE
            if not (entry_offset <= offset < entry_offset + entry_size):
                continue
            chunk_index = (offset - entry_offset) // wii_chunk_size
            if chunk_index >= entry.group_count:
                return False
            chunk_start = entry_offset + chunk_index * wii_chunk_size
            chunk_logical_size = min(wii_chunk_size, entry_offset + entry_size - chunk_start)
            exception_list_count = max(1, wii_chunk_size // _WII_GROUP_DATA_SIZE)
            group = self._read_partition_group(
                entry.group_index + chunk_index, chunk_logical_size, chunk_start, exception_list_count
            )
            if group is None:
                return False
            offset_in_chunk = offset - chunk_start
            if offset_in_chunk + len(destination) > len(group.main_data):
                return False
            destination[:] = group.main_data[offset_in_chunk:offset_in_chunk + len(destination)]
            return True
        return False

    def _collect_wii_hash_exceptions(self, partition: _WiiPartition, group_start: int) -> list:
        exceptions = []
        group_end = group_start + _WII_GROUP_DATA_SIZE
        wii_chunk_size = self._chunk_size * _WII_CLUSTER_DATA_SIZE // _SECTOR_SIZE
        for entry in partition.data_entries:
            entry_offset = (entry.first_sector - partition.first_sector) * _WII_CLUSTER_DATA_SIZE
            entry_size = entry.number_of_sectors * _WII_CLUSTER_DATA_SIZE
            overlap_start = max(entry_offset, group_start)
            overlap_end = min(entry_offset + entry_size, group_end)
            if overlap_start >= overlap_end:
                continue

            first_chunk = (overlap_start - entry_offset) // wii_chunk_size
            last_chunk = (overlap_end - entry_offset - 1) // wii_chunk_size
            for chunk_index in range(first_chunk, last_chunk + 1):
                if chunk_index >= entry.group_count:
                    continue
                chunk_start = entry_offset + chunk_index * wii_chunk_size
                chunk_logical_size = min(wii_chunk_size, entry_offset + entry_size - chunk_start)
                exception_list_count = max(1, wii_chunk_size // _WII_GROUP_DATA_SIZE)
                partition_group = self._read_partition_group(
                    entry.group_index + chunk_index, chunk_logical_size, chunk_start, exception_list_count
                )
                if partition_group is None:
                    continue

                exception_list_index = 0 if exception_list_count == 1 else (group_start - chunk_start) // _WII_GROUP_DATA_SIZE
                if not (0 <= exception_list_index < len(partition_group.exception_lists)):
                    continue
                additional_offset = ((chunk_start % _WII_GROUP_DATA_SIZE) // _WII_CLUSTER_DATA_SIZE) * _WII_CLUSTER_HEADER_SIZE
                for exception in partition_group.exception_lists[exception_list_index]:
                    exceptions.append(_HashException(exception.offset + additional_offset, exception.hash))
        return exceptions

    def _read_partition_group(self, group_index: int, logical_size: int, group_logical_start: int, exception_list_count: int):
        if self._partition_group_index == group_index:
            cached = self._partition_group
            if cached is not None and len(cached.main_data) >= logical_size:
                return cached

        group_entry = self._group_entries[group_index]
        stored_size = group_entry.data_size & _GROUP_SIZE_MASK
        if stored_size == 0:
            result = _PartitionGroup(main_data=bytes(logical_size), exception_lists=[[] for _ in range(exception_list_count)])
            self._partition_group_index = group_index
            self._partition_group = result
            return result

        encoded = self._read_exact(group_entry.data_offset << 2, stored_size)
        uses_compression = group_entry.uses_file_compression
        decompressed = _decompress_unknown_size(encoded) if uses_compression else encoded

        exception_lists, main_data_offset = _parse_exception_lists(
            decompressed, exception_list_count, align_last=not uses_compression
        )
        packed_main_data = decompressed[main_data_offset:]
        if group_entry.packed_size > 0:
            padded = packed_main_data[:group_entry.packed_size].ljust(group_entry.packed_size, b"\x00")
            main_data = _decode_rvz_packed(padded, logical_size, group_logical_start)
        else:
            if len(packed_main_data) < logical_size:
                return None
            main_data = packed_main_data[:logical_size]

        result = _PartitionGroup(main_data=main_data, exception_lists=exception_lists)
        self._partition_group_index = group_index
        self._partition_group = result
        return result

    def _read_group(self, group_index: int, logical_size: int, group_logical_start: int) -> bytes:
        if self._raw_group_index == group_index:
            cached = self._raw_group_data
            if cached is not None and len(cached) >= logical_size:
                return cached

        group_entry = self._group_entries[group_index]
        stored_size = group_entry.data_size & _GROUP_SIZE_MASK
        if stored_size == 0:
            result = bytes(logical_size)
            self._raw_group_index = group_index
            self._raw_group_data = result
            return result

        encoded = self._read_exact(group_entry.data_offset << 2, stored_size)
        if group_entry.uses_file_compression:
            expected = group_entry.packed_size if group_entry.packed_size > 0 else logical_size
            decompressed = _decompress(encoded, self._file_compression_type, expected)
        else:
            decompressed = encoded

        if group_entry.packed_size > 0:
            result = _decode_rvz_packed(decompressed, logical_size, group_logical_start)
        else:
            if len(decompressed) < logical_size:
                raise RvzParseError("RVZ group is shorter than expected logical size")
            result = decompressed[:logical_size]

        self._raw_group_index = group_index
        self._raw_group_data = result
        return result

    def _read_exact(self, offset: int, size: int) -> bytes:
        return _read_fully(self._read_source, offset, size)


def _decompress(encoded: bytes, compression_type: int, expected_size: int) -> bytes:
    if compression_type == _COMPRESSION_NONE:
        return encoded
    if compression_type == _COMPRESSION_ZSTD:
        try:
            return zstd_decompress(encoded, expected_size)
        except CodecError as exc:
            raise RvzParseError(str(exc)) from exc
    raise RvzParseError(f"Unsupported RVZ compression type={compression_type}")


def _decompress_unknown_size(encoded: bytes) -> bytes:
    try:
        expected_size = zstd_frame_content_size(encoded)
        return zstd_decompress(encoded, expected_size)
    except CodecError as exc:
        raise RvzParseError(str(exc)) from exc


def _read_fully(read_source, offset: int, size: int) -> bytes:
    if size <= 0:
        return b""
    out = bytearray()
    while len(out) < size:
        chunk = read_source.read(offset + len(out), size - len(out))
        if not chunk:
            raise RvzParseError("Unexpected EOF while reading RVZ data")
        out += chunk
    return bytes(out)


def _read_metadata_block(read_source, offset: int, compressed_size: int, compression_type: int, expected_size: int) -> bytes:
    encoded = _read_fully(read_source, offset, compressed_size)
    if compression_type == _COMPRESSION_NONE:
        return encoded
    if compression_type == _COMPRESSION_ZSTD:
        try:
            return zstd_decompress(encoded, expected_size)
        except CodecError as exc:
            raise RvzParseError(f"RVZ metadata decompress failed: {exc}") from exc
    raise RvzParseError(f"Unsupported RVZ metadata compression type={compression_type}")


def _parse_partition_entries(data: bytes, count: int, entry_size: int) -> list:
    partitions = []
    for index in range(count):
        offset = index * entry_size
        raw_entry = data[offset:offset + entry_size]
        entry = raw_entry[:_PARTITION_ENTRY_SIZE].ljust(_PARTITION_ENTRY_SIZE, b"\x00")

        data_entries = []
        for entry_index in range(2):
            entry_offset = 16 + entry_index * _PARTITION_DATA_ENTRY_SIZE
            first_sector = _be_u32(entry, entry_offset)
            number_of_sectors = _be_u32(entry, entry_offset + 4)
            group_index = _be_u32(entry, entry_offset + 8)
            group_count = _be_u32(entry, entry_offset + 12)
            if number_of_sectors > 0:
                data_entries.append(_WiiPartitionDataEntry(first_sector, number_of_sectors, group_index, group_count))

        if not data_entries:
            continue

        first_sector = data_entries[0].first_sector
        if len(data_entries) > 1:
            total_sectors = (data_entries[1].first_sector - first_sector) + data_entries[1].number_of_sectors
        else:
            total_sectors = data_entries[0].number_of_sectors

        partitions.append(_WiiPartition(
            key=entry[0:16],
            data_entries=data_entries,
            first_sector=first_sector,
            total_sectors=total_sectors,
        ))
    return partitions


def _parse_raw_entries(data: bytes, count: int) -> list:
    entries = []
    for index in range(count):
        offset = index * _RAW_DATA_ENTRY_SIZE
        raw_offset = _be_u64(data, offset)
        raw_size = _be_u64(data, offset + 8)
        group_index = _be_u32(data, offset + 16)
        group_count = _be_u32(data, offset + 20)
        skipped_data = raw_offset % _SECTOR_SIZE
        logical_start = raw_offset - skipped_data
        logical_end = logical_start + raw_size + skipped_data
        entries.append(_RawDataEntry(logical_start, logical_end, group_index, group_count))
    return entries


def _parse_group_entries(data: bytes, count: int) -> list:
    entries = []
    for index in range(count):
        offset = index * _GROUP_ENTRY_SIZE
        data_offset = _be_u32(data, offset)
        data_size = _be_u32(data, offset + 4)
        packed_size = _be_u32(data, offset + 8)
        entries.append(_GroupEntry(data_offset, data_size, packed_size))
    return entries


def _parse_exception_lists(data: bytes, exception_list_count: int, align_last: bool):
    offset = 0
    lists = []
    for index in range(exception_list_count):
        count = _be_u16(data, offset)
        offset += 2
        entries = []
        for i in range(count):
            entry_offset = offset + i * _HASH_EXCEPTION_ENTRY_SIZE
            exception_offset = _be_u16(data, entry_offset)
            exception_hash = data[entry_offset + 2:entry_offset + _HASH_EXCEPTION_ENTRY_SIZE]
            entries.append(_HashException(exception_offset, exception_hash))
        offset += count * _HASH_EXCEPTION_ENTRY_SIZE
        if align_last and index == exception_list_count - 1:
            offset = _align_to_4(offset)
        lists.append(entries)
    return lists, offset


def _decode_rvz_packed(packed: bytes, logical_size: int, group_logical_start: int) -> bytes:
    output = bytearray(logical_size)
    input_offset = 0
    output_offset = 0

    while input_offset < len(packed) and output_offset < logical_size:
        record_size = _be_i32(packed, input_offset)
        input_offset += 4
        generated = record_size < 0
        size = record_size & _GROUP_SIZE_MASK

        if not generated:
            if input_offset + size > len(packed) or output_offset + size > logical_size:
                raise RvzParseError("Invalid RVZ packed copy record")
            output[output_offset:output_offset + size] = packed[input_offset:input_offset + size]
            input_offset += size
            output_offset += size
            continue

        if input_offset + _SEED_SIZE > len(packed) or output_offset + size > logical_size:
            raise RvzParseError("Invalid RVZ packed PRNG record")

        seed = [_be_i32(packed, input_offset + i * 4) & _MASK32 for i in range(17)]
        input_offset += _SEED_SIZE
        generated_bytes = _generate_rvz_bytes(seed, size, group_logical_start + output_offset)
        output[output_offset:output_offset + size] = generated_bytes
        output_offset += size

    if output_offset != logical_size:
        raise RvzParseError(f"RVZ packed output truncated expected={logical_size} actual={output_offset}")

    return bytes(output)


def _generate_rvz_bytes(seed: list, size: int, absolute_offset: int) -> bytes:
    buffer = [0] * 521
    for index in range(len(seed)):
        buffer[index] = seed[index]
    for index in range(17, len(buffer)):
        buffer[index] = ((buffer[index - 17] << 23) & _MASK32) ^ (buffer[index - 16] >> 9) ^ buffer[index - 1]
    for _ in range(4):
        _advance_lagged_fibonacci(buffer)

    word_index = 0
    bytes_to_skip = absolute_offset % _SECTOR_SIZE
    if bytes_to_skip > 0:
        word_index = _write_lagged_fibonacci_bytes(buffer, bytearray(bytes_to_skip), bytes_to_skip, word_index)

    output = bytearray(size)
    _write_lagged_fibonacci_bytes(buffer, output, size, word_index)
    return bytes(output)


def _write_lagged_fibonacci_bytes(buffer: list, output: bytearray, byte_count: int, initial_word_index: int) -> int:
    word_index = initial_word_index
    output_offset = 0
    while output_offset < byte_count:
        if word_index == len(buffer):
            _advance_lagged_fibonacci(buffer)
            word_index = 0
        value = buffer[word_index]
        word_index += 1
        word_bytes = bytes((
            (value >> 24) & 0xFF,
            (value >> 18) & 0xFF,
            (value >> 8) & 0xFF,
            value & 0xFF,
        ))
        count = min(len(word_bytes), byte_count - output_offset)
        output[output_offset:output_offset + count] = word_bytes[:count]
        output_offset += count
    return word_index


def _advance_lagged_fibonacci(buffer: list) -> None:
    length = len(buffer)
    for index in range(32):
        buffer[index] ^= buffer[index + length - 32]
    for index in range(32, length):
        buffer[index] ^= buffer[index - 32]


def _build_wii_hash_blocks(blocks: list) -> list:
    headers = [bytearray(_WII_CLUSTER_HEADER_SIZE) for _ in range(_WII_GROUP_BLOCK_COUNT)]
    subgroup_hashes = [b""] * 8

    for block_index in range(_WII_GROUP_BLOCK_COUNT):
        header = headers[block_index]
        for chunk_index in range(31):
            digest = _sha1(bytes(blocks[block_index][chunk_index * _WII_CLUSTER_HEADER_SIZE:chunk_index * _WII_CLUSTER_HEADER_SIZE + _WII_CLUSTER_HEADER_SIZE]))
            header[chunk_index * 20:chunk_index * 20 + 20] = digest
        subgroup_index = block_index // 8
        position_in_subgroup = block_index % 8
        h1 = _sha1(bytes(header[0:31 * 20]))
        headers[subgroup_index * 8][0x280 + position_in_subgroup * 20:0x280 + position_in_subgroup * 20 + 20] = h1

    for subgroup_index in range(8):
        source = headers[subgroup_index * 8]
        subgroup_hashes[subgroup_index] = _sha1(bytes(source[0x280:0x280 + 8 * 20]))
        for copy_index in range(1, 8):
            headers[subgroup_index * 8 + copy_index][0x280:0x340] = source[0x280:0x340]

    h2_source = b"".join(subgroup_hashes)
    h2_hashes = [h2_source[i * 20:i * 20 + 20] for i in range(8)]
    for block_index in range(_WII_GROUP_BLOCK_COUNT):
        header = headers[block_index]
        for hash_index in range(8):
            header[0x340 + hash_index * 20:0x340 + hash_index * 20 + 20] = h2_hashes[hash_index]

    return headers


def _apply_wii_hash_exceptions(hash_blocks: list, exceptions: list) -> None:
    for exception in exceptions:
        block_index = exception.offset // _WII_CLUSTER_HEADER_SIZE
        offset_in_block = exception.offset % _WII_CLUSTER_HEADER_SIZE
        if not (0 <= block_index < len(hash_blocks)) or offset_in_block + len(exception.hash) > _WII_CLUSTER_HEADER_SIZE:
            raise RvzParseError(f"Invalid RVZ Wii hash exception offset={exception.offset}")
        hash_blocks[block_index][offset_in_block:offset_in_block + len(exception.hash)] = exception.hash
