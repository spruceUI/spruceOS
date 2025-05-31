--[[--
Zip packing workflow & code from luarocks' zip.lua :
   https://github.com/luarocks/luarocks/blob/master/src/luarocks/tools/zip.lua
 Modified to not require lua-zlib (we can wrap zlib with ffi)
   cf: http://luajit.org/ext_ffi_tutorial.html, which uses zlib as an example !
 Simplified to take filename and content from strings and not from disk

@module ffi.zipwriter
]]

-- We only need a few functions from zlib
local bit = require "bit"
local ffi = require "ffi"
require "ffi/zlib_h"

-- We only need to wrap 2 zlib functions to make a zip file
local _zlib = ffi.load(ffi.os == "Windows" and "zlib1" or "z")
local function zlibCompress(data)
    local n = _zlib.compressBound(#data)
    local buf = ffi.new("uint8_t[?]", n)
    local buflen = ffi.new("unsigned long[1]", n)
    local res = _zlib.compress2(buf, buflen, data, #data, 9)
    assert(res == 0)
    return ffi.string(buf, buflen[0])
end
local function zlibCrc32(data, chksum)
    chksum = chksum or 0
    data = data or ""
    return _zlib.crc32(chksum, data, #data)
end

local function numberToByteString(number, nbytes)
    local out = {}
    for _ = 1, nbytes do
        local byte = number % 256
        table.insert(out, string.char(byte))
        number = (number - byte) / 256
    end
    return table.concat(out)
end


-- Pure lua zip writer
local ZipWriter = {}

function ZipWriter:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self
    return o
end

--- Begin a new file to be stored inside the zipfile.
function ZipWriter:_open_new_file_in_zip(filename)
    if self.in_open_file then
        self:_close_file_in_zip()
        return nil
    end
    local lfh = {}
    self.local_file_header = lfh
    lfh.last_mod_file_time = self.started_time -- 0 = 00:00
    lfh.last_mod_file_date = self.started_date -- 0 = 1980-00-00 00:00
    lfh.file_name_length = #filename
    lfh.extra_field_length = 0
    lfh.file_name = filename:gsub("\\", "/")
    lfh.external_attr = 0
    self.in_open_file = true
    return true
end

--- Write data to the file currently being stored in the zipfile.
function ZipWriter:_write_file_in_zip(data, no_compression)
    if not self.in_open_file then
        return nil
    end
    local lfh = self.local_file_header
    lfh.crc32 = tonumber(zlibCrc32(data))
    lfh.uncompressed_size = #data
    if no_compression then
        lfh.compressed_size = lfh.uncompressed_size
        self.data = data
        lfh._no_compression = true
    else
        local compressed = zlibCompress(data):sub(3, -5)
        lfh.compressed_size = #compressed
        self.data = compressed
    end
    return true
end

--- Complete the writing of a file stored in the zipfile.
function ZipWriter:_close_file_in_zip()
    local zh = self.ziphandle
    if not self.in_open_file then
        return nil
    end
    -- Local file header
    local lfh = self.local_file_header
    lfh.offset = zh:seek()
    zh:write(numberToByteString(0x04034b50, 4)) -- signature
    zh:write(numberToByteString(20, 2)) -- version needed to extract: 2.0
    zh:write(numberToByteString(0, 2)) -- general purpose bit flag
    if lfh._no_compression then
        zh:write(numberToByteString(0, 2)) -- compression method: store
    else
        zh:write(numberToByteString(8, 2)) -- compression method: deflate
    end
    zh:write(numberToByteString(lfh.last_mod_file_time, 2))
    zh:write(numberToByteString(lfh.last_mod_file_date, 2))
    zh:write(numberToByteString(lfh.crc32, 4))
    zh:write(numberToByteString(lfh.compressed_size, 4))
    zh:write(numberToByteString(lfh.uncompressed_size, 4))
    zh:write(numberToByteString(lfh.file_name_length, 2))
    zh:write(numberToByteString(lfh.extra_field_length, 2))
    zh:write(lfh.file_name)
    -- File data
    zh:write(self.data)
    -- Data descriptor
    zh:write(numberToByteString(lfh.crc32, 4))
    zh:write(numberToByteString(lfh.compressed_size, 4))
    zh:write(numberToByteString(lfh.uncompressed_size, 4))
    -- Done, add it to list of files
    table.insert(self.files, lfh)
    self.in_open_file = false
    return true
end

--- Complete the writing of the zipfile.
function ZipWriter:close()
    local zh = self.ziphandle
    local central_directory_offset = zh:seek()
    local size_of_central_directory = 0
    -- Central directory structure
    for _, lfh in ipairs(self.files) do
        zh:write(numberToByteString(0x02014b50, 4)) -- signature
        zh:write(numberToByteString(3, 2)) -- version made by: UNIX
        zh:write(numberToByteString(20, 2)) -- version needed to extract: 2.0
        zh:write(numberToByteString(0, 2)) -- general purpose bit flag
        if lfh._no_compression then
            zh:write(numberToByteString(0, 2)) -- compression method: store
        else
            zh:write(numberToByteString(8, 2)) -- compression method: deflate
        end
        zh:write(numberToByteString(lfh.last_mod_file_time, 2))
        zh:write(numberToByteString(lfh.last_mod_file_date, 2))
        zh:write(numberToByteString(lfh.crc32, 4))
        zh:write(numberToByteString(lfh.compressed_size, 4))
        zh:write(numberToByteString(lfh.uncompressed_size, 4))
        zh:write(numberToByteString(lfh.file_name_length, 2))
        zh:write(numberToByteString(lfh.extra_field_length, 2))
        zh:write(numberToByteString(0, 2)) -- file comment length
        zh:write(numberToByteString(0, 2)) -- disk number start
        zh:write(numberToByteString(0, 2)) -- internal file attributes
        zh:write(numberToByteString(lfh.external_attr, 4)) -- external file attributes
        zh:write(numberToByteString(lfh.offset, 4)) -- relative offset of local header
        zh:write(lfh.file_name)
        size_of_central_directory = size_of_central_directory + 46 + lfh.file_name_length
    end
    -- End of central directory record
    zh:write(numberToByteString(0x06054b50, 4)) -- signature
    zh:write(numberToByteString(0, 2)) -- number of this disk
    zh:write(numberToByteString(0, 2)) -- number of disk with start of central directory
    zh:write(numberToByteString(#self.files, 2)) -- total number of entries in the central dir on this disk
    zh:write(numberToByteString(#self.files, 2)) -- total number of entries in the central dir
    zh:write(numberToByteString(size_of_central_directory, 4))
    zh:write(numberToByteString(central_directory_offset, 4))
    zh:write(numberToByteString(0, 2)) -- zip file comment length
    zh:close()
    return true
end

-- Open zipfile
function ZipWriter:open(zipfilepath)
    self.files = {}
    self.in_open_file = false
    -- set modification date and time of files to now
    local t = os.date("*t")
    self.started_date = bit.bor(
        bit.lshift(t.year-1980, 9),
        bit.lshift(t.month,     5),
        bit.lshift(t.day,       0)
    )
    self.started_time = bit.bor(
        bit.lshift(t.hour,     11),
        bit.lshift(t.min,       5),
        bit.rshift(t.sec+2,     1)
    )
    self.ziphandle = io.open(zipfilepath, "wb")
    if not self.ziphandle then
        return nil
    end
    return true
end

-- Add to zipfile content with the name in_zip_filepath
function ZipWriter:add(in_zip_filepath, content, no_compression)
    self:_open_new_file_in_zip(in_zip_filepath)
    self:_write_file_in_zip(content, no_compression)
    self:_close_file_in_zip()
end

-- Convenience function
-- function ZipWriter.createZipWithFiles(zipfilename, files)
--     local zw = ZipWriter:new()
--     zw:open(zipfilename)
--     for _, f in pairs(files) do
--         zw:add(f.filename, f.content)
--     end
--     zw:close()
-- end
-- files = {}
-- files[1] = {filename="tutu.txt", content="this is tutu"}
-- files[2] = {filename="subtoto/toto.txt", content="this is toto in subtoto directory"}
-- createZipWithFiles("tata.zip", files)

return ZipWriter
