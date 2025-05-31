--[[--
MD5 hash library.


Deprecated except for sumFile. Use sha2 instead.

@module ffi.md5
]]

local sha2 = require "ffi/sha2"

local md5 = {}

--- Calculate md5 sum for a file.
---- @string filename
---- @treturn string md5 sum in Lua string
function md5.sumFile(filename)
    local update = sha2.md5()
    local fd, err = io.open(filename, "rb")
    if err ~= nil then
        return nil, err
    end
    while true do
        local bytes = fd:read(8192)
        if not bytes then
            fd:close()
            break
        end
        update(bytes)
    end
    return update()
end

return md5
