# Network Services Documentation

This document describes the network service architecture in SpruceOS, including SSH, Samba (SMB), Syncthing, SFTPGo, and Darkhttpd services. The network system allows wireless file sharing, remote access, and game synchronization.

## Table of Contents

1. [Network System Overview](#network-system-overview)
2. [Architecture](#architecture)
3. [SSH (Dropbear)](#ssh-dropbear)
4. [Samba (SMB/CIFS)](#samba-smbcifs)
5. [Syncthing](#syncthing)
6. [SFTPGo](#sftpgo)
7. [Darkhttpd](#darkhttpd)
8. [Configuration Management](#configuration-management)
9. [Common Tasks](#common-tasks)
10. [Troubleshooting](#troubleshooting)

## Network System Overview

### Purpose

The network services provide:

1. **SSH Access** - Remote command execution and login
2. **File Sharing** - Samba/SMB for Windows-compatible network shares
3. **Game/Data Sync** - Syncthing for automatic backup and synchronization
4. **Secure File Transfer** - SFTPGo for SFTP server
5. **Web Access** - Darkhttpd for simple HTTP file serving

### Service Architecture

```
networkservices.sh (main orchestrator)
    ├── Check WiFi connection
    ├── Check each service setting in system JSON
    ├── Start/stop services based on user preference
    └── Manage status and logging

Network Function Libraries:
    ├── network/sshFunctions.sh          (SSH/Dropbear)
    ├── network/sambaFunctions.sh        (SMB/Samba)
    ├── network/syncthingFunctions.sh    (Syncthing sync)
    ├── network/sftpgoFunctions.sh       (SFTP server)
    └── network/darkhttpdFunctions.sh    (HTTP server)
```

### Design Philosophy

- **Configuration-Driven** - User enables/disables via system JSON
- **Modular** - Each service is independent
- **Non-Intrusive** - Services don't interfere with emulation
- **Safe** - Stop services before game launch to maximize resources
- **Automatic** - Services auto-start on system boot if enabled

## Architecture

### Initialization Flow

```
runtime.sh
    ↓
helperFunctions.sh (device detection)
    ↓
runtimeHelper.sh
    ↓
networkservices.sh (main service manager)
    ├── While WiFi available:
    │   ├── Check: get_config_value '.menuOptions.Network.enableSSH.selected'
    │   ├── Check: get_config_value '.menuOptions.Network.enableSamba.selected'
    │   ├── Check: get_config_value '.menuOptions.Network.enableSyncthing.selected'
    │   ├── Check: get_config_value '.menuOptions.Network.enableSFTPGo.selected'
    │   └── Start/stop services accordingly
    └── Loop every 60 seconds
```

### Service Status Management

Services maintain state via flag files:

- `/mnt/SDCARD/spruce/flags/ssh_running` - SSH active
- `/mnt/SDCARD/spruce/flags/samba_running` - Samba active
- `/mnt/SDCARD/spruce/flags/syncthing_running` - Syncthing active
- `/mnt/SDCARD/spruce/flags/sftpgo_running` - SFTPGo active
- `/mnt/SDCARD/spruce/flags/darkhttpd_running` - Darkhttpd active

### Service Control

All services are managed as background daemons:

```bash
# Start service
start_ssh_process              # Runs as background daemon
flag_add "ssh_running"         # Mark as running

# Stop service
stop_ssh_process               # Gracefully stop daemon
flag_remove "ssh_running"      # Clear running flag

# Check status
if flag_check "ssh_running"; then
    echo "SSH is running"
fi
```

## SSH (Dropbear)

### Overview

Dropbear is a lightweight SSH server that provides secure remote command execution and file transfer.

**Default Port:** 22

**Features:**

- Secure command execution
- Secure file transfer (SCP/SFTP)
- Key-based authentication
- Password authentication (configurable)

### Configuration

#### Enable/Disable SSH

```bash
# Via system JSON
jq '.menuOptions.Network.enableSSH.selected' "$SYSTEM_JSON"
# Returns: "True" or "False"

# Set via config function
set_config_value '.menuOptions.Network.enableSSH.selected' 'True'
```

#### SSH Key Management

```bash
# Generate SSH host keys on first boot
dropbear_generate_keys
# Creates:
#   /etc/dropbear/dropbear_rsa_host_key
#   /etc/dropbear/dropbear_ed25519_host_key
```

### Functions

#### `dropbear_generate_keys()`

**Purpose:** Generate SSH host keys for secure connections

**When called:** First boot only (if keys don't exist)

**Generated Keys:**

- RSA host key (2048-bit)
- ED25519 host key (modern, smaller)

**Usage:**

```bash
source /mnt/SDCARD/spruce/scripts/network/sshFunctions.sh
dropbear_generate_keys
```

#### `start_ssh_process()`

**Purpose:** Start Dropbear SSH server daemon

**Port:** 22 (standard SSH)

**Configuration Files:**

- SSH keys: `/etc/dropbear/`
- Config: `/etc/dropbear/dropbear.conf` (if exists)

**Usage:**

```bash
source /mnt/SDCARD/spruce/scripts/network/sshFunctions.sh
start_ssh_process
# SSH now available: ssh root@<device_ip>
```

**Command:**

```bash
/usr/sbin/dropbear -p 22 -B
# -p 22 = port 22
# -B = background mode
```

#### `stop_ssh_process()`

**Purpose:** Stop Dropbear SSH server

**Usage:**

```bash
stop_ssh_process
# SSH server stopped
```

**Command:**

```bash
pkill -f dropbear || true
```

### Usage Examples

#### Connect to Device via SSH

From a computer on the same network:

```bash
# Get device IP
# (visible in network settings or router)

# Connect via SSH
ssh root@192.168.1.50

# Once connected, you can:
ls /mnt/SDCARD/Roms/      # List ROMs
cp game.gba /mnt/SDCARD/Roms/GBA/  # Copy files
cat /var/log/messages     # View system logs
```

#### Copy Files via SCP

```bash
# From computer to device
scp game.gb root@192.168.1.50:/mnt/SDCARD/Roms/GB/

# From device to computer
scp root@192.168.1.50:/mnt/SDCARD/Saves/GB/savegame.sav ./
```

#### SSH Keys (Advanced)

```bash
# Generate SSH keypair on your computer
ssh-keygen -t ed25519 -f ~/.ssh/sprucedevice

# Copy public key to device
ssh-copy-id -i ~/.ssh/sprucedevice.pub root@192.168.1.50

# Or manually copy to device
scp ~/.ssh/sprucedevice.pub root@192.168.1.50:/root/.ssh/authorized_keys

# Now login without password
ssh -i ~/.ssh/sprucedevice root@192.168.1.50
```

### Default Credentials

- **User:** root
- **Password:** (none or configured in system)
- **Authentication:** Key-based or password (if enabled)

## Samba (SMB/CIFS)

### Overview

Samba provides SMB/CIFS file sharing, allowing Windows/Mac computers to access device files as network shares.

**Default Port:** 445 (Windows SMB)

**Features:**

- Browse device files in Windows File Explorer
- Network drive mapping
- Drag-and-drop file transfer
- Username/password protection
- File permissions

### Configuration

#### Enable/Disable Samba

```bash
# Via system JSON
jq '.menuOptions.Network.enableSamba.selected' "$SYSTEM_JSON"
# Returns: "True" or "False"
```

#### Configuration Files

- **Samba config:** `/etc/samba/smb.conf`
- **Shares directory:** `/mnt/SDCARD/` (shared as "Roms", "Saves", etc.)

### Functions

#### `start_samba_process()`

**Purpose:** Start Samba daemon (smbd and nmbd)

**Usage:**

```bash
source /mnt/SDCARD/spruce/scripts/network/sambaFunctions.sh
start_samba_process
```

**Daemons Started:**

- `smbd` - Main SMB protocol handler
- `nmbd` - NetBIOS name service (helps device discovery)

#### `stop_samba_process()`

**Purpose:** Stop Samba daemon

**Usage:**

```bash
stop_samba_process
```

### Usage Examples

#### Connect from Windows

1. Open File Explorer
2. Right-click and select "Map network drive"
3. Enter: `\\192.168.1.50\Roms`
4. Enter credentials (root / password)
5. Files appear as network drive

#### Connect from Mac

1. Finder → Go → Connect to Server
2. Enter: `smb://192.168.1.50/Roms`
3. Enter credentials
4. Share mounts on desktop

#### Available Shares

The Samba configuration typically exposes:

```
\\192.168.1.50\Roms        → /mnt/SDCARD/Roms/
\\192.168.1.50\Saves       → /mnt/SDCARD/Saves/
\\192.168.1.50\BIOS        → /mnt/SDCARD/BIOS/
\\192.168.1.50\App         → /mnt/SDCARD/App/
\\192.168.1.50\Themes      → /mnt/SDCARD/Themes/
```

### Default Credentials

- **User:** root
- **Password:** (configured in smb.conf)

## Syncthing

### Overview

Syncthing provides automatic, bidirectional synchronization of files between the device and computers.

**Default Port:** 8384 (web UI), 22000 (sync)

**Features:**

- Automatic backup of game saves
- Sync across multiple computers
- Versioning (recover old file versions)
- Selective folder sync
- End-to-end encrypted (optional)
- Web UI for management

### Configuration

#### Enable/Disable Syncthing

```bash
# Via system JSON
jq '.menuOptions.Network.enableSyncthing.selected' "$SYSTEM_JSON"
# Returns: "True" or "False"
```

#### Configuration Files

- **Config:** `/home/root/.config/syncthing/config.xml`
- **Data:** `/home/root/.local/share/syncthing/`
- **Certificate:** `/home/root/.config/syncthing/cert.pem`

### Functions

#### `generate_syncthing_config()`

**Purpose:** Create initial Syncthing configuration

**Usage:**

```bash
source /mnt/SDCARD/spruce/scripts/network/syncthingFunctions.sh
generate_syncthing_config
```

**Creates:**

- Device ID (unique identifier)
- API key
- Configuration files
- Default folder syncs

#### `repair_syncthing_config()`

**Purpose:** Fix corrupted Syncthing configuration

**Usage:**

```bash
repair_syncthing_config
# Validates and repairs config.xml
# Restores default settings if needed
```

#### `start_syncthing_process()`

**Purpose:** Start Syncthing daemon (background)

**Usage:**

```bash
start_syncthing_process
# Syncthing running in background
# Web UI available at: http://192.168.1.50:8384
```

#### `run_syncthing()`

**Purpose:** Run Syncthing in foreground (main mode)

**Usage (rarely used directly):**

```bash
run_syncthing
# Syncthing runs in foreground with logs to console
```

### Usage Examples

#### Access Syncthing Web UI

1. On computer, open web browser
2. Navigate to: `http://192.168.1.50:8384`
3. Log in with credentials
4. Add folders to sync
5. Add other devices to share with

#### Add Another Device

1. Open Syncthing web UI
2. Click "Add Remote Device"
3. Enter device ID from other device
4. Confirm on remote device
5. Select folders to share

#### Sync Game Saves

1. Create shared folder: `/mnt/SDCARD/Saves/`
2. Add to Syncthing via web UI
3. Add device (e.g., laptop) to share
4. Game saves automatically sync

### Device ID Discovery

```bash
# Get Syncthing device ID
curl http://localhost:8384/rest/system/status | jq '.deviceID'
```

## SFTPGo

### Overview

SFTPGo provides a dedicated SFTP (SSH File Transfer Protocol) server with web administration interface.

**Default Ports:**

- 2022 (SFTP)
- 8080 (Web UI admin)

**Features:**

- Dedicated SFTP server (not SSH)
- Web UI for user/permission management
- Virtual filesystem paths
- Per-user quotas
- Audit logging

### Configuration

#### Enable/Disable SFTPGo

```bash
# Via system JSON
jq '.menuOptions.Network.enableSFTPGo.selected' "$SYSTEM_JSON"
# Returns: "True" or "False"
```

#### Configuration Files

- **Config:** `/etc/sftpgo/sftpgo.conf`
- **Users DB:** `/etc/sftpgo/users.db`

### Functions

#### `start_sftpgo_process()`

**Purpose:** Start SFTPGo server daemon

**Usage:**

```bash
source /mnt/SDCARD/spruce/scripts/network/sftpgoFunctions.sh
start_sftpgo_process
# SFTP available on port 2022
# Web UI available at: http://192.168.1.50:8080
```

#### `stop_sftpgo_process()`

**Purpose:** Stop SFTPGo server

**Usage:**

```bash
stop_sftpgo_process
```

### Usage Examples

#### Connect via SFTP Client

```bash
# Using command line
sftp -P 2022 root@192.168.1.50

# Using SFTP client (WinSCP, Cyberduck, etc.)
Host: 192.168.1.50
Port: 2022
User: (configured)
Password: (configured)

# Once connected
ls                          # List files
cd Roms/GB                  # Change directory
put game.gb                 # Upload file
get savegame.sav            # Download file
quit                        # Exit
```

#### Web Administration

1. Open browser: `http://192.168.1.50:8080`
2. Login with SFTPGo admin credentials
3. Manage users and permissions
4. Monitor connections
5. Set upload/download limits

## Darkhttpd

### Overview

Darkhttpd is a lightweight HTTP server for serving static files and directories.

**Default Port:** 8008

**Features:**

- Zero configuration needed
- Serves entire SD card directory tree
- CGI script support (optional)
- Directory listings
- Range requests (resume downloads)

### Configuration

Darkhttpd is auto-configured to serve `/mnt/SDCARD/` on port 8008.

### Functions

#### `start_darkhttpd_process()`

**Purpose:** Start Darkhttpd server daemon

**Usage:**

```bash
source /mnt/SDCARD/spruce/scripts/network/darkhttpdFunctions.sh
start_darkhttpd_process
# Web server available at: http://192.168.1.50:8008
```

#### `stop_darkhttpd_process()`

**Purpose:** Stop Darkhttpd server

**Usage:**

```bash
stop_darkhttpd_process
```

### Usage Examples

#### Access Files via Browser

1. Open web browser: `http://192.168.1.50:8008`
2. Navigate directory structure
3. Download ROMs, saves, etc.
4. Browse themes and screenshots

#### Download Game Saves

```
http://192.168.1.50:8008/Saves/GB/           # Browse saves
http://192.168.1.50:8008/Saves/GB/game.sav   # Download directly
```

#### Directory Listing

```
http://192.168.1.50:8008/Roms/               # Browse ROMs
http://192.168.1.50:8008/Roms/GB/            # Browse by system
http://192.168.1.50:8008/Roms/GB/game.gb     # Direct file link
```

## Configuration Management

### System JSON Settings

All network services are configured via the `menuOptions.Network` section:

```json
{
  "menuOptions": {
    "Network Settings": {
      "enableSSH": {
        "selected": "True",
        "options": ["True", "False"]
      },
      "enableSamba": {
        "selected": "False",
        "options": ["True", "False"]
      },
      "enableSFTPGo": {
        "selected": "False",
        "options": ["True", "False"]
      },
      "enableSyncthing": {
        "selected": "False",
        "options": ["True", "False"]
      },
      "darkhttpdEnabled": {
        "selected": "Auto",
        "options": ["Auto", "On", "Off"]
      }
    }
  }
}
```

### Service Detection

```bash
# Check if service should be running
SSH_ENABLED=$(get_config_value '.menuOptions.Network.enableSSH.selected')

if [ "$SSH_ENABLED" = "True" ]; then
    start_ssh_process
else
    stop_ssh_process
fi
```

### Configuration Updates

```bash
# Enable SSH
set_config_value '.menuOptions.Network.enableSSH.selected' 'True'

# Disable Samba
set_config_value '.menuOptions.Network.enableSamba.selected' 'False'

# These changes take effect next time networkservices.sh checks (max 60 seconds)
```

## Common Tasks

### Check Network Service Status

```bash
# Check individual services
ps aux | grep -E "dropbear|smbd|syncthing|sftpgo|darkhttpd"

# Or via flag system
flag_check "ssh_running"
flag_check "samba_running"
flag_check "syncthing_running"
```

### View Service Logs

```bash
# System log messages
tail -f /var/log/messages | grep -i network

# Application-specific logs
tail -f /mnt/SDCARD/Saves/spruce/spruce.log
```

### Stop All Services

```bash
# Via system JSON
set_config_value '.menuOptions.Network.enableSSH.selected' 'False'
set_config_value '.menuOptions.Network.enableSamba.selected' 'False'
set_config_value '.menuOptions.Network.enableSyncthing.selected' 'False'
set_config_value '.menuOptions.Network.enableSFTPGo.selected' 'False'

# Manual stop
pkill -f dropbear
pkill -f smbd
pkill -f nmbd
pkill -f syncthing
pkill -f sftpgo
pkill -f darkhttpd
```

### Get Device Network Information

```bash
# IP address
hostname -I

# Network interfaces
ifconfig

# Connected WiFi network
iw dev wlan0 link

# Route information
ip route show
```

### Network Troubleshooting

```bash
# Check WiFi connectivity
ping -c 3 8.8.8.8

# Check DNS resolution
nslookup google.com

# Device discovery (mDNS)
avahi-resolve-address <device_ip>

# Open ports
netstat -tulpn | grep LISTEN
```

## Troubleshooting

### SSH Won't Start

```bash
# Check if port 22 is available
netstat -tulpn | grep 22

# Check SSH keys exist
ls -la /etc/dropbear/

# If missing, regenerate
dropbear_generate_keys

# Try starting with debug output
dropbear -p 22 -F -v
```

### Samba Share Not Visible

```bash
# Check Samba is running
ps aux | grep smbd

# Test SMB connectivity
smbclient -L //192.168.1.50 -U root

# Check configuration
cat /etc/samba/smb.conf
```

### Syncthing Folder Not Syncing

```bash
# Check Syncthing is running
ps aux | grep syncthing

# Access web UI
curl http://localhost:8384/rest/system/connections

# Check folder permissions
ls -la /mnt/SDCARD/Saves/

# Repair config if corrupted
repair_syncthing_config
```

### Can't Connect to Device Over WiFi

```bash
# Check device IP
hostname -I

# Check WiFi is enabled
ifconfig wlan0

# Check signal quality
iw dev wlan0 link

# Restart DHCP
killall dhclient
dhclient wlan0

# Test ping from computer
ping <device_ip>
```

### Services Stop After Game Launch

This is expected behavior:

```bash
# Services are stopped before game to free resources
# They restart after game exits (configurable delay)

# Game launch process:
1. Stop all network services
2. Set CPU to performance
3. Launch emulator/game
4. On exit: Restart network services
```

### High CPU Usage from Syncthing

Syncthing can be CPU-intensive during initial sync:

```bash
# Monitor CPU usage
top -p $(pgrep syncthing)

# Disable temporarily
stop_syncthing_process

# Check what's syncing
# (via web UI at http://192.168.1.50:8384)
```

## Network Security Notes

### Recommendations

1. **Change Default Passwords** - If using password auth
2. **Use SSH Keys** - More secure than password authentication
3. **Restrict Access** - Use firewall rules if available
4. **Keep Services Updated** - Regular updates recommended
5. **Monitor Logs** - Check for unauthorized access attempts
6. **Enable Service Selectively** - Keep only needed services running

### Default Network Ports

| Service        | Port     | Protocol |
| -------------- | -------- | -------- |
| SSH (Dropbear) | 22       | TCP      |
| Samba          | 445, 139 | TCP      |
| Syncthing      | 22000    | TCP/UDP  |
| Syncthing UI   | 8384     | HTTP     |
| SFTPGo         | 2022     | TCP      |
| SFTPGo UI      | 8080     | HTTP     |
| Darkhttpd      | 8008     | HTTP     |

### Firewall Recommendations

If device has firewall:

```bash
# Allow SSH from LAN
ufw allow from 192.168.1.0/24 to any port 22

# Allow Samba from LAN
ufw allow from 192.168.1.0/24 to any port 445

# Block SFTP from WAN
ufw deny from any to any port 2022/tcp
```
