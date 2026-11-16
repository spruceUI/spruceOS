import ctypes
import fcntl
import os
import queue
import threading
import wave

from utils.logger import PyUiLogger


class AudioPlayerOss:
    """Menu sounds through /dev/dsp, for the Miyoo Mini: libpadsp (preloaded by
    launch.sh) hands them to audioserver, which owns the audio hardware. Plays
    wav only; loops and mp3 are not supported."""

    SNDCTL_DSP_SPEED = 0xC0045002
    SNDCTL_DSP_SETFMT = 0xC0045005
    SNDCTL_DSP_CHANNELS = 0xC0045006
    AFMT_U8 = 0x08
    AFMT_S16_LE = 0x10

    def __init__(self):
        self._sounds = {}
        self._libc = ctypes.CDLL(None, use_errno=True)
        self._queue = queue.Queue(maxsize=1)
        threading.Thread(target=self._worker, daemon=True).start()

    def _load(self, file_path):
        if file_path not in self._sounds:
            try:
                with wave.open(file_path, "rb") as w:
                    self._sounds[file_path] = (w.getframerate(), w.getnchannels(),
                                               w.getsampwidth(), w.readframes(w.getnframes()))
            except Exception as e:
                PyUiLogger.get_logger().warning(f"Cannot load {file_path}: {e}")
                self._sounds[file_path] = None
        return self._sounds[file_path]

    def _play(self, sound):
        rate, channels, width, frames = sound
        # libpadsp hooks open() but not the open64() that os.open() calls.
        fd = self._libc.open(b"/dev/dsp", os.O_WRONLY)
        if fd < 0:
            raise OSError(ctypes.get_errno(), "open /dev/dsp")
        try:
            fmt = self.AFMT_S16_LE if width == 2 else self.AFMT_U8
            for request, value in ((self.SNDCTL_DSP_SETFMT, fmt),
                                   (self.SNDCTL_DSP_CHANNELS, channels),
                                   (self.SNDCTL_DSP_SPEED, rate)):
                fcntl.ioctl(fd, request, value.to_bytes(4, "little"))
            os.write(fd, frames)
        finally:
            os.close(fd)

    def _worker(self):
        while True:
            file_path = self._queue.get()
            sound = self._load(file_path)
            if sound is None:
                continue
            try:
                self._play(sound)
            except OSError as e:
                PyUiLogger.get_logger().warning(f"Cannot play {file_path}: {e}")

    def audio_set_volume(self, volume: int):
        pass

    def audio_play_wav(self, file_path: str):
        try:
            self._queue.put_nowait(file_path)
        except queue.Full:
            pass

    def audio_loop_wav(self, file_path: str):
        pass

    def audio_loop_mp3(self, file_path: str):
        pass

    def audio_stop_loop(self):
        pass

    def load_wav(self, file_path: str):
        self._load(file_path)

    def audio_reopen(self):
        pass
