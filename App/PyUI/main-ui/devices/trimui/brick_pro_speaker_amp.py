import atexit
import subprocess
import threading
import time

from audio.audio_player_delegate_sdl2 import AudioPlayerDelegateSdl2
from utils.logger import PyUiLogger

# Brick Pro: the speaker amp ('HpSpeaker Switch') stays on at idle and
# amplifies board noise into an audible hiss (spruceOS#1616). Every switch of
# the amp makes a small pop, on and off, so it is not switched per sound: it
# comes on right before any menu sound and goes off only after this long
# without one, while no game is running and no menu music is looping.
IDLE_OFF_SECONDS = 15
POLL_SECONDS = 1.0
AMP_CONTROL = "name=HpSpeaker Switch"


class BrickProSpeakerAmpGate(AudioPlayerDelegateSdl2):
    """The SDL2 audio player, plus gating of the Brick Pro speaker amp."""

    def __init__(self, start_gate=True):
        super().__init__()
        self._lock = threading.Lock()
        self._amp_on = None          # unknown until first set
        self._looping = False
        self._last_sound = time.monotonic()
        if start_gate:
            atexit.register(self._set_amp, True)  # never leave games silent
            threading.Thread(target=self._idle_loop, daemon=True).start()

    def _set_amp(self, on):
        with self._lock:
            if self._amp_on == on:
                return
            try:
                subprocess.run(["amixer", "-q", "-c", "0", "cset", AMP_CONTROL, "on" if on else "off"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
                self._amp_on = on
                PyUiLogger.get_logger().info(f"Speaker amp {'on' if on else 'off'}")
            except Exception as e:
                PyUiLogger.get_logger().warning(f"Speaker amp switch failed: {e}")

    def hold_amp_on(self, seconds=10):
        """Amp on now and for at least `seconds`: for handing the speaker to a
        game or app. PyUI usually exits right after (os._exit skips atexit),
        so this must not depend on how PyUI ends."""
        self._last_sound = time.monotonic() + seconds
        self._set_amp(True)

    def _sound_starting(self):
        self._last_sound = time.monotonic()
        self._set_amp(True)

    def _idle_loop(self):
        from controller.controller import Controller
        was_in_game = False
        while True:
            time.sleep(POLL_SECONDS)
            in_game = Controller._game_running
            if was_in_game and not in_game:
                self._last_sound = time.monotonic()  # back in the menu: idle timer restarts
            was_in_game = in_game
            if in_game or self._looping:
                self._set_amp(True)
            elif time.monotonic() - self._last_sound >= IDLE_OFF_SECONDS:
                self._set_amp(False)

    def audio_play_wav(self, file_path: str):
        self._sound_starting()
        super().audio_play_wav(file_path)

    def audio_loop_wav(self, file_path: str):
        self._looping = True
        self._sound_starting()
        super().audio_loop_wav(file_path)

    def audio_loop_mp3(self, file_path: str):
        self._looping = True
        self._sound_starting()
        super().audio_loop_mp3(file_path)

    def audio_stop_loop(self):
        super().audio_stop_loop()
        self._looping = False
        self._last_sound = time.monotonic()
