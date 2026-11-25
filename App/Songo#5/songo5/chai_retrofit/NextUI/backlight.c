// NextUI backlight helper for the CHAI retrofit.
//
// Usage: backlight get       prints the current backlight, 0-255
//        backlight set N     sets the backlight to N (0-255) without
//                            touching NextUI's saved brightness
//
// Does exactly what NextUI's libmsettings SetRawBrightness() does on tg5040
// and h700: a DISP_LCD_SET_BRIGHTNESS ioctl on /dev/disp. Reads it back with
// DISP_LCD_GET_BRIGHTNESS, so "get" sees the real hardware value, including
// 0 after a fade-out.
//
// It doesn't load libmsettings.so itself. That would need a binary linked
// against the device's glibc, and the library's InitSettings() re-applies
// NextUI's saved brightness and volume on every call, which would undo a
// fade. tg5050 uses /sys/class/backlight/backlight0 instead of /dev/disp;
// this exits 2 there and chai falls back to the default profile's sysfs code.
//
// Build: aarch64-linux-gnu-gcc -O2 -static -s -o backlight backlight.c

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define DISP_LCD_SET_BRIGHTNESS 0x102
#define DISP_LCD_GET_BRIGHTNESS 0x103

int main(int argc, char *argv[]) {
	if (argc < 2 || (strcmp(argv[1], "set") == 0 && argc < 3)) {
		fprintf(stderr, "usage: %s get | set N\n", argv[0]);
		return 1;
	}

	int fd = open("/dev/disp", O_RDWR);
	if (fd < 0) return 2;

	unsigned long param[4] = {0, 0, 0, 0};
	int rc = 0;

	if (strcmp(argv[1], "get") == 0) {
		int val = ioctl(fd, DISP_LCD_GET_BRIGHTNESS, &param);
		if (val < 0) rc = 1;
		else printf("%d\n", val > 255 ? 255 : val);
	}
	else if (strcmp(argv[1], "set") == 0) {
		int val = atoi(argv[2]);
		if (val < 0) val = 0;
		if (val > 255) val = 255;
		param[1] = val;
		if (ioctl(fd, DISP_LCD_SET_BRIGHTNESS, &param) < 0) rc = 1;
	}
	else {
		rc = 1;
	}

	close(fd);
	return rc;
}
