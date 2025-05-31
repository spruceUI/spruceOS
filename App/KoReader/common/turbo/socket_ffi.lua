--- Turbo.lua Socket Module
--
-- Copyright 2013 John Abrahamsen
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local log = require "turbo.log"
local util = require "turbo.util"
local bit = jit and require "bit" or require "bit32"
local ffi = require "ffi"
local platform = require "turbo.platform"
require "turbo.cdef"

local octal = function (s) return tonumber(s, 8) end
local hex = function (s) return tonumber(s, 16) end

local F = {}
F.F_DUPFD =             0
F.F_GETFD =             1
F.F_SETFD =             2
F.F_GETFL =             3
F.F_SETFL =             4

local O = {}
if ffi.arch == "mipsel" then
	O.O_ACCMODE =           octal("0003")
	O.O_RDONLY =            octal("00")
	O.O_WRONLY =            octal("01")
	O.O_RDWR =              octal("02")
	O.O_CREAT =             octal("0400")   
	O.O_EXCL =              octal("2000")   
	O.O_NOCTTY =            octal("4000")   
	O.O_TRUNC =             octal("1000")
	O.O_APPEND =            octal("0010")
	O.O_NONBLOCK =          octal("0200")
	O.O_NDELAY =            O.O_NONBLOCK
	O.O_SYNC =              octal("0020")
	O.O_FSYNC =             O.O_SYNC
	O.O_ASYNC =             octal("10000")
else
	O.O_ACCMODE =           octal("0003")
	O.O_RDONLY =            octal("00")
	O.O_WRONLY =            octal("01")
	O.O_RDWR =              octal("02")
	O.O_CREAT =             octal("0100")   
	O.O_EXCL =              octal("0200")   
	O.O_NOCTTY =            octal("0400")   
	O.O_TRUNC =             octal("01000")
	O.O_APPEND =            octal("02000")
	O.O_NONBLOCK =          octal("04000")
	O.O_NDELAY =            O.O_NONBLOCK
	O.O_SYNC =              octal("04010000")
	O.O_FSYNC =             O.O_SYNC
	O.O_ASYNC =             octal("020000")
end

local SOCK = {}
if ffi.arch == "mipsel" then
	SOCK.SOCK_STREAM =      2
	SOCK.SOCK_DGRAM =       1
	SOCK.SOCK_RAW =         3
	SOCK.SOCK_RDM =         4
	SOCK.SOCK_SEQPACKET =   5
	SOCK.SOCK_DCCP =        6   
	SOCK.SOCK_PACKET =      10
	SOCK.SOCK_CLOEXEC =     octal("02000000")
	SOCK.SOCK_NONBLOCK =    octal("0200")
else
	SOCK.SOCK_STREAM =      1
	SOCK.SOCK_DGRAM =       2
	SOCK.SOCK_RAW =         3
	SOCK.SOCK_RDM =         4
	SOCK.SOCK_SEQPACKET =   5
	SOCK.SOCK_DCCP =        6   
	SOCK.SOCK_PACKET =      10
	SOCK.SOCK_CLOEXEC =     octal("02000000")
	SOCK.SOCK_NONBLOCK =    octal("040009")
end

--[[ Protocol families.  ]]
local PF = {}
PF.PF_UNSPEC =          0       --[[ Unspecified.  ]]
PF.PF_LOCAL =           1       --[[ Local to host (pipes and file-domain).  ]]
PF.PF_UNIX =            PF.PF_LOCAL     --[[ POSIX name for PF.PF_LOCAL.  ]]
PF.PF_FILE =            PF.PF_LOCAL     --[[ Another non-standard name for PF.PF_LOCAL.  ]]
PF.PF_INET =            2       --[[ IP protocol family.  ]]
PF.PF_AX25 =            3       --[[ Amateur Radio AX.25.  ]]
PF.PF_IPX =             4       --[[ Novell Internet Protocol.  ]]
PF.PF_APPLETALK =       5       --[[ Appletalk DDP.  ]]
PF.PF_NETROM =          6       --[[ Amateur radio NetROM.  ]]
PF.PF_BRIDGE =          7       --[[ Multiprotocol bridge.  ]]
PF.PF_ATMPVC =          8       --[[ ATM PVCs.  ]]
PF.PF_X25 =             9       --[[ Reserved for X.25 project.  ]]
PF.PF_INET6 =           10      --[[ IP version 6.  ]]
PF.PF_ROSE =            11      --[[ Amateur Radio X.25 PLP.  ]]
PF.PF_DECnet =          12      --[[ Reserved for DECnet project.  ]]
PF.PF_NETBEUI =         13      --[[ Reserved for 802.2LLC project.  ]]
PF.PF_SECURITY =        14      --[[ Security callback pseudo AF.  ]]
PF.PF_KEY =             15      --[[ PF.PF_KEY key management API.  ]]
PF.PF_NETLINK =         16
PF.PF_ROUTE =           PF.PF_NETLINK   --[[ Alias to emulate 4.4BSD.  ]]
PF.PF_PACKET =          17      --[[ Packet family.  ]]
PF.PF_ASH =             18      --[[ Ash.  ]]
PF.PF_ECONET =          19      --[[ Acorn Econet.  ]]
PF.PF_ATMSVC =          20      --[[ ATM SVCs.  ]]
PF.PF_RDS =             21      --[[ RDS sockets.  ]]
PF.PF_SNA =             22      --[[ Linux SNA Project ]]
PF.PF_IRDA =            23      --[[ IRDA sockets.  ]]
PF.PF_PPPOX =           24      --[[ PPPoX sockets.  ]]
PF.PF_WANPIPE =         25      --[[ Wanpipe API sockets.  ]]
PF.PF_LLC =             26      --[[ Linux LLC.  ]]
PF.PF_CAN =             29      --[[ Controller Area Network.  ]]
PF.PF_TIPC =            30      --[[ TIPC sockets.  ]]
PF.PF_BLUETOOTH =       31      --[[ Bluetooth sockets.  ]]
PF.PF_IUCV =            32      --[[ IUCV sockets.  ]]
PF.PF_RXRPC =           33      --[[ RxRPC sockets.  ]]
PF.PF_ISDN =            34      --[[ mISDN sockets.  ]]
PF.PF_PHONET =          35      --[[ Phonet sockets.  ]]
PF.PF_IEEE802154 =      36      --[[ IEEE 802.15.4 sockets.  ]]
PF.PF_CAIF =            37      --[[ CAIF sockets.  ]]
PF.PF_ALG =             38      --[[ Algorithm sockets.  ]]
PF.PF_NFC =             39      --[[ NFC sockets.  ]]
PF.PF_MAX =             40      --[[ For now..  ]]


--[[ Address families.  ]]
local AF = {}
AF.AF_UNSPEC =          PF.PF_UNSPEC
AF.AF_LOCAL =           PF.PF_LOCAL
AF.AF_UNIX =            PF.PF_UNIX
AF.AF_FILE =            PF.PF_FILE
AF.AF_INET =            PF.PF_INET
AF.AF_AX25 =            PF.PF_AX25
AF.AF_IPX =             PF.PF_IPX
AF.AF_APPLETALK =       PF.PF_APPLETALK
AF.AF_NETROM =          PF.PF_NETROM
AF.AF_BRIDGE =          PF.PF_BRIDGE
AF.AF_ATMPVC =          PF.PF_ATMPVC
AF.AF_X25 =             PF.PF_X25
AF.AF_INET6 =           PF.PF_INET6
AF.AF_ROSE =            PF.PF_ROSE
AF.AF_DECnet =          PF.PF_DECnet
AF.AF_NETBEUI =         PF.PF_NETBEUI
AF.AF_SECURITY =        PF.PF_SECURITY
AF.AF_KEY =             PF.PF_KEY
AF.AF_NETLINK =         PF.PF_NETLINK
AF.AF_ROUTE =           PF.PF_ROUTE
AF.AF_PACKET =          PF.PF_PACKET
AF.AF_ASH =             PF.PF_ASH
AF.AF_ECONET =          PF.PF_ECONET
AF.AF_ATMSVC =          PF.PF_ATMSVC
AF.AF_RDS =             PF.PF_RDS
AF.AF_SNA =             PF.PF_SNA
AF.AF_IRDA =            PF.PF_IRDA
AF.AF_PPPOX =           PF.PF_PPPOX
AF.AF_WANPIPE =         PF.PF_WANPIPE
AF.AF_LLC =             PF.PF_LLC
AF.AF_CAN =             PF.PF_CAN
AF.AF_TIPC =            PF.PF_TIPC
AF.AF_BLUETOOTH =       PF.PF_BLUETOOTH
AF.AF_IUCV =            PF.PF_IUCV
AF.AF_RXRPC =           PF.PF_RXRPC
AF.AF_ISDN =            PF.PF_ISDN
AF.AF_PHONET =          PF.PF_PHONET
AF.AF_IEEE802154 =      PF.PF_IEEE802154
AF.AF_CAIF =            PF.PF_CAIF
AF.AF_ALG =             PF.PF_ALG
AF.AF_NFC =             PF.PF_NFC
AF.AF_MAX =             PF.PF_MAX

local SOL = {}
if ffi.arch == "mipsel" then
SOL.SOL_SOCKET =        octal("177777")	-- 0xFFFF
else
SOL.SOL_SOCKET =        1
end

local SO = {}
if ffi.arch == "mipsel" then
SO.SO_DEBUG =           1
SO.SO_REUSEADDR =       4
SO.SO_TYPE =            hex("1008")
SO.SO_ERROR =           hex("1007")
SO.SO_DONTROUTE =       hex("0010")
SO.SO_BROADCAST =       hex("0020")
SO.SO_SNDBUF =          hex("1001")
SO.SO_RCVBUF =          hex("1002")
SO.SO_SNDBUFFORCE =     31
SO.SO_RCVBUFFORCE =     33
SO.SO_KEEPALIVE =       8
SO.SO_OOBINLINE =       hex("0100")
SO.SO_NO_CHECK =        11
SO.SO_PRIORITY =        12
SO.SO_LINGER =          hex("0080")
SO.SO_BSDCOMPAT =       14
SO.SO_PASSCRED =        17
SO.SO_PEERCRED =        18
SO.SO_RCVLOWAT =        hex("1004")
SO.SO_SNDLOWAT =        hex("1003")
SO.SO_RCVTIMEO =        hex("1006")
SO.SO_SNDTIMEO =        hex("1005")
SO.SO_SECURITY_AUTHENTICATION =            22
SO.SO_SECURITY_ENCRYPTION_TRANSPORT =      23
SO.SO_SECURITY_ENCRYPTION_NETWORK =        24
SO.SO_BINDTODEVICE =    25
SO.SO_ATTACH_FILTER =   26
SO.SO_DETACH_FILTER =   27
SO.SO_PEERNAME =        28
SO.SO_TIMESTAMP =       29
SO.SCM_TIMESTAMP =      SO.SO_TIMESTAMP
SO.SO_ACCEPTCONN =      hex("1009")
SO.SO_PEERSEC =         30
SO.SO_PASSSEC =         34
SO.SO_TIMESTAMPNS =     35
SCM_TIMESTAMPNS =       SO.SO_TIMESTAMPNS
SO.SO_MARK =            36
SO.SO_TIMESTAMPING =    37
SO.SCM_TIMESTAMPING=    SO.SO_TIMESTAMPING
SO.SO_PROTOCOL =        hex("1028")
SO.SO_DOMAIN =          hex("1029")
SO.SO_RXQ_OVFL =        40
--SO.SO_WIFI_STATUS =     41
--SO.SCM_WIFI_STATUS =    SO.SO_WIFI_STATUS
--SO.SO_PEEK_OFF =        42
--SO.SO_NOFCS =           43
else
SO.SO_DEBUG =           1
SO.SO_REUSEADDR =       2
SO.SO_TYPE =            3
SO.SO_ERROR =           4
SO.SO_DONTROUTE =       5
SO.SO_BROADCAST =       6
SO.SO_SNDBUF =          7
SO.SO_RCVBUF =          8
SO.SO_SNDBUFFORCE =     32
SO.SO_RCVBUFFORCE =     33
SO.SO_KEEPALIVE =       9
SO.SO_OOBINLINE =       10
SO.SO_NO_CHECK =        11
SO.SO_PRIORITY =        12
SO.SO_LINGER =          13
SO.SO_BSDCOMPAT =       14
SO.SO_PASSCRED =        16
SO.SO_PEERCRED =        17
SO.SO_RCVLOWAT =        18
SO.SO_SNDLOWAT =        19
SO.SO_RCVTIMEO =        20
SO.SO_SNDTIMEO =        21
SO.SO_SECURITY_AUTHENTICATION =            22
SO.SO_SECURITY_ENCRYPTION_TRANSPORT =      23
SO.SO_SECURITY_ENCRYPTION_NETWORK =        24
SO.SO_BINDTODEVICE =    25
SO.SO_ATTACH_FILTER =   26
SO.SO_DETACH_FILTER =   27
SO.SO_PEERNAME =        28
SO.SO_TIMESTAMP =       29
SO.SCM_TIMESTAMP =      SO.SO_TIMESTAMP
SO.SO_ACCEPTCONN =      30
SO.SO_PEERSEC =         31
SO.SO_PASSSEC =         34
SO.SO_TIMESTAMPNS =     35
SCM_TIMESTAMPNS =       SO.SO_TIMESTAMPNS
SO.SO_MARK =            36
SO.SO_TIMESTAMPING =    37
SO.SCM_TIMESTAMPING=    SO.SO_TIMESTAMPING
SO.SO_PROTOCOL =        38
SO.SO_DOMAIN =          39
SO.SO_RXQ_OVFL =        40
SO.SO_WIFI_STATUS =     41
SO.SCM_WIFI_STATUS =    SO.SO_WIFI_STATUS
SO.SO_PEEK_OFF =        42
SO.SO_NOFCS =           43
end

local E
if ffi.arch == "mipsel" then
E = {
    EAGAIN =            11,
    EWOULDBLOCK =       11,
    EINPROGRESS =       150,
    ECONNRESET =        131,
    EPIPE =             32,
    EAI_AGAIN =         3
}
else
E = {
    EAGAIN =            11,
    EWOULDBLOCK =       11,
    EINPROGRESS =       115,
    ECONNRESET =        104,
    EPIPE =             32,
    EAI_AGAIN =         3
}
end


if platform.__LINUX__ and not _G.__TURBO_USE_LUASOCKET__ then
    -- Linux FFI functions.

    local function strerror(errno)
        local cstr = ffi.C.strerror(errno);
        return ffi.string(cstr);
    end

    local function resolv_hostname(str)
        local in_addr_arr = {}
        local hostent = ffi.C.gethostbyname(str)
        if hostent == nil then
           return -1
        end
        local inaddr = ffi.cast("struct in_addr **", hostent.h_addr_list)
        local i = 0
        while inaddr[i] ~= nil do
           in_addr_arr[#in_addr_arr + 1] = inaddr[i][0]
           i = i + 1
        end
        return {
            in_addr = in_addr_arr,
            addrtype = tonumber(hostent.h_addrtype),
            name = ffi.string(hostent.h_name)
        }

    end

    local function set_nonblock_flag(fd)
        local flags = ffi.C.fcntl(fd, F.F_GETFL, 0);
        if flags == -1 then
           return -1, "fcntl GETFL failed."
        end
        if (bit.band(flags, O.O_NONBLOCK) ~= 0) then
           return 0
        end
        flags = bit.bor(flags, O.O_NONBLOCK)
        local rc = ffi.C.fcntl(fd, F.F_SETFL, flags)
        if rc == -1 then
           return -1, "fcntl set O_NONBLOCK failed."
        end
        return 0
    end

    local setopt = ffi.new("int32_t[1]")
    local function set_reuseaddr_opt(fd)
        setopt[0] = 1
        local rc = ffi.C.setsockopt(fd,
            SOL.SOL_SOCKET,
            SO.SO_REUSEADDR,
            setopt,
            ffi.sizeof("int32_t"))
        if rc ~= 0 then
           errno = ffi.errno()
           return -1, string.format("setsockopt SO_REUSEADDR failed. %s",
                                    strerror(errno))
        end
        return 0
    end

    --- Create new non blocking socket for use in IOStream.
    -- If family or stream type is not set AF_INET and SOCK_STREAM is used.
    local function new_nonblock_socket(family, stype, protocol)
        local fd = ffi.C.socket(family or AF.AF_INET,
                                stype or SOCK.SOCK_STREAM,
                                protocol or 0)

        if fd == -1 then
           errno = ffi.errno()
           return -1, string.format("Could not create socket. %s", strerror(errno))
        end
        local rc, msg = set_nonblock_flag(fd)
        if (rc ~= 0) then
           return rc, msg
        end
        return fd
    end

    local value = ffi.new("int32_t[1]")
    local socklen = ffi.new("socklen_t[1]", ffi.sizeof("int32_t"))
    local function get_socket_error(fd)
        local rc = ffi.C.getsockopt(fd,
            SOL.SOL_SOCKET,
            SO.SO_ERROR,
            ffi.cast("void *", value),
            socklen)
        if rc ~= 0 then
           return -1
        else
           return 0, tonumber(value[0])
        end
    end

    local export = util.tablemerge(SOCK,
        util.tablemerge(F,
        util.tablemerge(O,
        util.tablemerge(AF,
        util.tablemerge(PF,
        util.tablemerge(SOL,
        util.tablemerge(SO, E)))))))

    return util.tablemerge({
        strerror = strerror,
        resolv_hostname = resolv_hostname,
        getaddrinfo = ffi.C.getaddrinfo,
        set_nonblock_flag = set_nonblock_flag,
        set_reuseaddr_opt = set_reuseaddr_opt,
        new_nonblock_socket = new_nonblock_socket,
        get_socket_error = get_socket_error,
        INADDR_ANY = 0x00000000,
        INADDR_BROADCAST = 0xffffffff,
        INADDR_NONE =   0xffffffff,
    }, export)

else
    -- LuaSocket version.

    local luasocket = require "socket"

    --- Create new non blocking socket for use in IOStream.
    -- If family or stream type is not set AF_INET and SOCK_STREAM is used.
    local function new_nonblock_socket(family, stype, protocol)
        family = family or AF.AF_INET
        stype = stype or SOCK.SOCK_STREAM
        assert(family == AF.AF_INET or AF.AF_INET6,
            "LuaSocket only support AF_INET or AF_INET6")
        assert(stype == SOCK.SOCK_DGRAM or SOCK.SOCK_STREAM,
            "LuaSocket only support SOCK_DGRAM and SOCK_STREAM.")
        local sock
        if stype == SOCK.SOCK_DGRAM then
            sock = luasocket.udp()
        elseif stype == SOCK.SOCK_STREAM then
            sock = luasocket.tcp()
        end
        sock:settimeout(0)
        sock:setoption("keepalive", true)
        return sock
    end

    local export = util.tablemerge(SOCK,
        util.tablemerge(F,
        util.tablemerge(O,
        util.tablemerge(AF,
        util.tablemerge(PF,
        util.tablemerge(SOL,
        util.tablemerge(SO, E)))))))
    return util.tablemerge({
        new_nonblock_socket = new_nonblock_socket,
        INADDR_ANY = 0x00000000,
        INADDR_BROADCAST = 0xffffffff,
        INADDR_NONE = 0xffffffff,
    }, export)
end
