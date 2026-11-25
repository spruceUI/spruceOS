// NextUI volume listener for the CHAI retrofit.
//
// Usage: vol_listener <chai command>
// Runs "<chai command> notify-volume VOLUME 100" on every volume change.
//
// keymon owns the volume keys: it reads them and calls SetVolume(), which
// updates the ALSA mixer and /dev/shm/SharedSettings. Nothing announces the
// change, and at the min/max keymon doesn't call SetVolume at all, so:
//   - key events tell us *when* to send (including attempts at the limit)
//   - SharedSettings tells us *what* to send (never our own counter)
//
// Sleeps in poll() until an input event arrives; only polls on a short
// timeout while a volume key is held.

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <errno.h>
#include <signal.h>
#include <time.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>

#define CODE_PLUS   115  // KEY_VOLUMEUP
#define CODE_MINUS  114  // KEY_VOLUMEDOWN
#define CODE_MENU0  314  // + vol = colortemp in keymon
#define CODE_MENU2  316  // + vol = brightness in keymon

#define PRESSED  1
#define RELEASED 0

#define VOLUME_MIN 0
#define VOLUME_MAX 20

#define SHM_PATH "/dev/shm/SharedSettings"
#define MUTE_NO_CHANGE -69  // SETTINGS_DEFAULT_MUTE_NO_CHANGE

// Settings struct offsets (in ints). Everything up to toggled_volume is shared,
// but tg5050 (SettingsV1/V2) lacks disable_dpad_on_mute and
// emulate_joystick_on_mute, so jack/audiosink sit 2 ints earlier than tg5040 (V10/V11).
#define IDX_VERSION        0
#define IDX_HEADPHONES     3
#define IDX_SPEAKER        4
#define IDX_MUTE           5
#define IDX_TOGGLED_VOLUME 14
#define IDX_JACK_TG5040    27
#define IDX_JACK_TG5050    25  // audiosink is always jack + 1

#define MAX_INPUTS 16

#define SETTLE_MS     80   // max wait for keymon to apply a press (it runs at ~60fps)
#define HELD_POLL_MS  10
#define REPEAT_DELAY  300  // keymon's hold-to-repeat timing
#define REPEAT_EVERY  100

static volatile sig_atomic_t quit = 0;
static void on_term(int sig) { quit = 1; }

static const volatile int *settings = NULL;
static size_t settings_ints = 0;

static uint64_t now_ms(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

// keymon creates the shm at boot, but retry lazily in case we started first
static int map_settings(void) {
	if (settings) return 1;

	int fd = open(SHM_PATH, O_RDONLY | O_CLOEXEC);
	if (fd < 0) return 0;

	struct stat st;
	if (fstat(fd, &st) != 0 || st.st_size < (off_t)((IDX_JACK_TG5050 + 2) * sizeof(int))) {
		close(fd);
		return 0;
	}

	void *p = mmap(NULL, st.st_size, PROT_READ, MAP_SHARED, fd, 0);
	close(fd);
	if (p == MAP_FAILED) return 0;

	settings = p;
	settings_ints = st.st_size / sizeof(int);
	return 1;
}

// Mirrors msettings GetVolume(), returns 0-20 or -1 if unavailable
static int get_volume(void) {
	if (!map_settings()) return -1;

	int idx_jack = settings[IDX_VERSION] <= 2 ? IDX_JACK_TG5050 : IDX_JACK_TG5040;
	if ((size_t)idx_jack + 1 >= settings_ints) idx_jack = IDX_JACK_TG5050;

	int volume;
	int toggled = settings[IDX_TOGGLED_VOLUME];

	if (settings[IDX_MUTE] && toggled != MUTE_NO_CHANGE)
		volume = toggled;
	else if (settings[idx_jack] || settings[idx_jack + 1] != 0)
		volume = settings[IDX_HEADPHONES];
	else
		volume = settings[IDX_SPEAKER];

	if (volume < VOLUME_MIN) volume = VOLUME_MIN;
	if (volume > VOLUME_MAX) volume = VOLUME_MAX;
	return volume;
}

static const char *chai_cmd = NULL;

// Runs chai in a child so a slow subscriber never delays the next key event.
// SIGCHLD is ignored in main, so children are reaped automatically.
static void notify_volume(int volume) {
	int scaled = (volume * 100) / VOLUME_MAX;

	char buf[16];
	snprintf(buf, sizeof(buf), "%d", scaled);

	pid_t pid = fork();
	if (pid == 0) {
		execl("/bin/sh", "sh", chai_cmd, "notify-volume", buf, "100", (char *)NULL);
		_exit(127);
	}

	printf("VOL -> %d (%d%%)\n", volume, scaled);
	fflush(stdout);
}

// Only keep devices that can report volume or menu keys
static int wants_device(int fd) {
	uint8_t keys[KEY_MAX / 8 + 1] = {0};
	if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keys)), keys) < 0) return 0;

	int codes[] = {CODE_PLUS, CODE_MINUS, CODE_MENU0, CODE_MENU2};
	for (size_t i = 0; i < sizeof(codes) / sizeof(codes[0]); i++) {
		if (keys[codes[i] / 8] & (1 << (codes[i] % 8))) return 1;
	}
	return 0;
}

static int at_limit(int volume, int dir) {
	return (dir > 0 && volume >= VOLUME_MAX) || (dir < 0 && volume <= VOLUME_MIN);
}

int main(int argc, char **argv) {
	if (argc < 2) {
		fprintf(stderr, "usage: %s <chai command>\n", argv[0]);
		return 1;
	}
	chai_cmd = argv[1];

	struct sigaction sa = {0};
	sa.sa_handler = on_term;  // no SA_RESTART so poll() returns on signal
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGINT, &sa, NULL);
	signal(SIGCHLD, SIG_IGN);

	struct pollfd fds[MAX_INPUTS];
	int nfds = 0;

	char path[32];
	for (int i = 0; i < MAX_INPUTS; i++) {
		snprintf(path, sizeof(path), "/dev/input/event%d", i);
		int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
		if (fd < 0) continue;
		if (!wants_device(fd)) {
			close(fd);
			continue;
		}
		fds[nfds].fd = fd;
		fds[nfds].events = POLLIN;
		nfds++;
	}

	if (nfds == 0) {
		fprintf(stderr, "vol_listener: no input devices with volume keys\n");
		return 1;
	}

	map_settings();

	int menu_pressed = 0;
	int menu2_pressed = 0;

	int held_dir = 0;        // +1 / -1 while a volume key is down
	uint64_t press_at = 0;

	int pending = 0;         // a press is waiting for keymon to apply it
	int pending_dir = 0;     // direction of that press, survives a quick release
	int baseline = -1;       // volume at the moment of the press

	int last_sent = -1;
	uint64_t last_sent_at = 0;

	struct input_event ev;

	while (!quit) {
		int timeout = (pending || held_dir) ? HELD_POLL_MS : -1;
		int ret = poll(fds, nfds, timeout);
		if (ret < 0 && errno != EINTR) break;

		for (int i = 0; i < nfds && ret > 0; i++) {
			if (!(fds[i].revents & POLLIN)) continue;

			while (read(fds[i].fd, &ev, sizeof(ev)) == sizeof(ev)) {
				// Repeats are ignored, keymon runs its own repeat timer
				if (ev.type != EV_KEY || ev.value > PRESSED) continue;

				switch (ev.code) {
					case CODE_MENU2:
						menu_pressed = ev.value;
						break;
					case CODE_MENU0:
						menu2_pressed = ev.value;
						break;
					case CODE_PLUS:
					case CODE_MINUS:
						if (ev.value == RELEASED) {
							held_dir = 0;
							break;
						}
						// Menu + vol is brightness / colortemp, not volume
						if (menu_pressed || menu2_pressed) break;

						held_dir = ev.code == CODE_PLUS ? 1 : -1;
						press_at = now_ms();
						baseline = get_volume();
						pending_dir = held_dir;
						pending = 1;
						break;
					default:
						break;
				}
			}
		}

		if (!pending && !held_dir) continue;

		uint64_t now = now_ms();
		int volume = get_volume();
		if (volume < 0) {
			pending = 0;
			continue;
		}

		if (pending) {
			// Send once keymon has applied the press, or right away if the
			// press can't change anything (already at the limit, muted level)
			if (volume != baseline || at_limit(volume, pending_dir) || now - press_at >= SETTLE_MS) {
				notify_volume(volume);
				last_sent = volume;
				last_sent_at = now;
				pending = 0;
			}
		}
		else if (held_dir) {
			if (volume != last_sent) {
				notify_volume(volume);
				last_sent = volume;
				last_sent_at = now;
			}
			// Held at the limit: keep re-sending on keymon's repeat cadence
			else if (at_limit(volume, held_dir) && now - press_at >= REPEAT_DELAY && now - last_sent_at >= REPEAT_EVERY) {
				notify_volume(volume);
				last_sent_at = now;
			}
		}
	}

	for (int i = 0; i < nfds; i++)
		close(fds[i].fd);

	return 0;
}
