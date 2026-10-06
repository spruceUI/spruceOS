import atexit
import subprocess
import threading
import time

from audio.audio_player_delegate_sdl2 import AudioPlayerDelegateSdl2
from utils.logger import PyUiLogger

# Brick Pro: the speaker amp ('HpSpeaker Switch') stays on at idle and
# amplifies board noise into an audible hiss (spruceOS#1616). It comes on
# right before every menu sound and goes off shortly after the last one, so
# the menu is silent between sounds. Every switch makes a small pop (on and
# off); fast navigation keeps the amp on, so pops only come at the start and
# end of a burst. Event-driven: nothing runs while the menu is quiet.
OFF_AFTER_SOUND_SECONDS = 0.5   # covers the 71 ms click plus output latency
GAME_RECHECK_SECONDS = 2.0      # only while a game runs with PyUI still alive
AMP_CONTROL = "name=HpSpeaker Switch"


class BrickProSpeakerAmpGate(AudioPlayerDelegateSdl2):
    """The SDL2 audio player, plus gating of the Brick Pro speaker amp."""

    def __init__(self, start_gate=True):
        super().__init__()
        self._amp_lock = threading.Lock()
        self._amp_on = None          # unknown until first set
        self._looping = False
        self._cond = threading.Condition()
        self._off_at = None          # monotonic time to switch off; None = nothing pending
        if start_gate:
            atexit.register(self._set_amp, True)  # never leave games silent
            threading.Thread(target=self._off_worker, daemon=True).start()
            self._schedule_off(OFF_AFTER_SOUND_SECONDS)  # quiet from startup

    def _set_amp(self, on):
        with self._amp_lock:
            if self._amp_on == on:
                return
            try:
                subprocess.run(["amixer", "-q", "-c", "0", "cset", AMP_CONTROL, "on" if on else "off"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
                self._amp_on = on
                PyUiLogger.get_logger().info(f"Speaker amp {'on' if on else 'off'}")
            except Exception as e:
                PyUiLogger.get_logger().warning(f"Speaker amp switch failed: {e}")

    def _schedule_off(self, delay):
        with self._cond:
            self._off_at = time.monotonic() + delay
            self._cond.notify()

    def _off_worker(self):
        from controller.controller import Controller
        with self._cond:
            while True:
                if self._off_at is None:
                    self._cond.wait()                    # quiet: sleep until a sound
                    continue
                remaining = self._off_at - time.monotonic()
                if remaining > 0:
                    self._cond.wait(remaining)           # a newer sound moves _off_at
                    continue
                if Controller._game_running or self._looping:
                    self._off_at = time.monotonic() + GAME_RECHECK_SECONDS
                    continue
                self._off_at = None
                self._set_amp(False)

    def hold_amp_on(self, seconds=10):
        """Amp on now and for at least `seconds`: for handing the speaker to a
        game or app. PyUI usually exits right after (os._exit skips atexit),
        so this must not depend on how PyUI ends."""
        self._set_amp(True)
        self._schedule_off(seconds)

    def _sound_starting(self):
        self._set_amp(True)
        self._schedule_off(OFF_AFTER_SOUND_SECONDS)

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
        self._schedule_off(OFF_AFTER_SOUND_SECONDS)
