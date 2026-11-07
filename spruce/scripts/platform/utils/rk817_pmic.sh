#!/bin/sh

# Mainline (ROCKNIX) leaves fuel gauge data in RK817 0x99/0xa4; the BSP kernel
# restores regulator enables from them at poweroff and reboot: dArkMoss comes
# back up after a poweroff, the Flip stays off after a reboot.
clear_stale_pmic_power_en() {
    "$DEVICE_PYTHON3_PATH" - <<'EOF' | while read -r line; do log_message "$line"; done
import fcntl, os
fd = os.open("/dev/i2c-0", os.O_RDWR)
fcntl.ioctl(fd, 0x0706, 0x20)
for reg in (0x99, 0xa4):
    os.write(fd, bytes([reg]))
    value = os.read(fd, 1)[0]
    if value:
        os.write(fd, bytes([reg, 0]))
        print(f"RK817: cleared stale 0x{reg:02x} (was 0x{value:02x})")
EOF
}
