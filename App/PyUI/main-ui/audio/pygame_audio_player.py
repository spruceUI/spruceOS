"""
Pygame (SDL1.2) audio player implementation
For use with legacy hardware like Miyoo Mini
"""

from pathlib import Path
import subprocess
import pygame
import pygame.mixer
import threading
import queue
from typing import Optional
from utils.logger import PyUiLogger
from utils.time_logger import log_timing


# Commands for the worker
class _Cmd:
    def __init__(self, name, args=(), kwargs=None, resp_q: Optional[queue.Queue] = None):
        self.name = name
        self.args = args
        self.kwargs = kwargs or {}
        self.resp_q = resp_q


class PygameAudioPlayer:
    # Worker state
    _worker_thread: Optional[threading.Thread] = None
    _cmd_q: Optional[queue.Queue] = None
    _running = False

    # Public state
    _initialized = False
    _init_failed = False
    _current_volume = 128  # 0..128 (SDL2 compatible range)

    @staticmethod
    def _ensure_worker():
        if PygameAudioPlayer._worker_thread and PygameAudioPlayer._running:
            return

        PygameAudioPlayer._cmd_q = queue.Queue()
        PygameAudioPlayer._running = True
        PygameAudioPlayer._worker_thread = threading.Thread(target=PygameAudioPlayer._worker_loop, daemon=True)
        PygameAudioPlayer._worker_thread.start()
        PyUiLogger.get_logger().info("PygameAudioPlayer worker thread started.")

    @staticmethod
    def _send_cmd(cmd_name, *args, expect_reply=False, **kwargs):
        PygameAudioPlayer._ensure_worker()
        resp_q = queue.Queue(maxsize=1) if expect_reply else None
        cmd = _Cmd(cmd_name, args=args, kwargs=kwargs, resp_q=resp_q)
        PygameAudioPlayer._cmd_q.put(cmd)
        if expect_reply:
            try:
                return resp_q.get(timeout=2.0)
            except queue.Empty:
                return None
        return None

    # Public API: these post commands to the worker and return immediately
    @staticmethod
    def _init():
        with log_timing("Pygame Audio initialization", PyUiLogger.get_logger()):
            res = PygameAudioPlayer._send_cmd("init", expect_reply=True)
            if res is True:
                PygameAudioPlayer._initialized = True
                PygameAudioPlayer._init_failed = False
            else:
                PygameAudioPlayer._initialized = False
                PygameAudioPlayer._init_failed = True

    @staticmethod
    def audio_set_volume(volume: int):
        """Set volume (0-10 range mapped to 0.0-1.0 for pygame)"""
        # Map 0..10 -> 0.0..1.0
        vol = max(0.0, min(1.0, volume / 10.0))
        PygameAudioPlayer._current_volume = int(volume * 12.8)  # Store as 0-128 for compatibility
        PygameAudioPlayer._send_cmd("set_volume", vol)

    @staticmethod
    def audio_play_wav(file_path: str):
        PygameAudioPlayer._send_cmd("play_wav_once", file_path)

    @staticmethod
    def audio_loop_wav(file_path: str):
        """Start looping a WAV file"""
        PygameAudioPlayer._send_cmd("start_loop_wav", file_path)

    @staticmethod
    def mp3_to_safe_ogg(mp3_path: str) -> Optional[str]:
        """
        Convert MP3 to OGG once. Returns path to OGG or None on failure.
        """
        src = Path(mp3_path)
        if not src.exists():
            return None

        safe_path = src.with_suffix(".__safe__.ogg")

        # Already converted?
        if safe_path.exists():
            return str(safe_path)

        PyUiLogger.get_logger().warning(f"Converting MP3 to safe OGG: {src.name}")

        try:
            result = subprocess.run(
                [
                    "ffmpeg",
                    "-y",  # overwrite if partial exists
                    "-v", "error",
                    "-i", str(src),
                    "-c:a", "libvorbis",
                    "-q:a", "4",
                    str(safe_path),
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=10,
            )
            if result.returncode != 0:
                PyUiLogger.get_logger().warning(f"FFmpeg failed converting {src}")
                return None

            return str(safe_path)

        except Exception as e:
            PyUiLogger.get_logger().warning(f"MP3 conversion exception for {src}: {e}")
            return None

    @staticmethod
    def audio_loop_mp3(file_path: str):
        """Start looping MP3 music (will convert to OGG if needed)"""
        PygameAudioPlayer._send_cmd("start_loop_music", file_path)

    @staticmethod
    def audio_stop_loop():
        """Stop any looping audio"""
        PygameAudioPlayer._send_cmd("stop_loop")

    @staticmethod
    def audio_cleanup():
        """Cleanup and stop worker"""
        PygameAudioPlayer._send_cmd("cleanup")
        if PygameAudioPlayer._worker_thread:
            PygameAudioPlayer._worker_thread.join(timeout=3.0)
        PygameAudioPlayer._worker_thread = None
        PygameAudioPlayer._cmd_q = None
        PygameAudioPlayer._running = False
        PygameAudioPlayer._initialized = False
        PygameAudioPlayer._init_failed = False
        PyUiLogger.get_logger().info("PygameAudioPlayer cleaned up.")

    @staticmethod
    def load_wav(file_path: str):
        """Preload a WAV file"""
        return PygameAudioPlayer._send_cmd("preload_wav", file_path, expect_reply=True)

    # --------------------------
    # Worker implementation below
    # --------------------------
    @staticmethod
    def _worker_loop():
        """
        All pygame.mixer calls happen here ONLY in worker thread.
        Commands come in through _cmd_q.
        """
        sound_map = {}  # path -> pygame.mixer.Sound
        loop_channel = None
        loop_music_path = None
        current_volume = 1.0

        def reply_ok(resp_q, ok=True):
            if resp_q:
                try:
                    resp_q.put(ok, timeout=0.5)
                except Exception:
                    pass

        def worker_init():
            """Initialize pygame mixer"""
            try:
                # Initialize pygame if not already done
                if not pygame.get_init():
                    pygame.init()

                # Initialize mixer with reasonable defaults
                # frequency, size, channels, buffer
                frequencies = [44100, 22050, 16000]
                for freq in frequencies:
                    try:
                        pygame.mixer.init(frequency=freq, size=-16, channels=2, buffer=1024)
                        PyUiLogger.get_logger().info(f"Pygame mixer initialized at {freq}Hz")
                        return True
                    except Exception as e:
                        PyUiLogger.get_logger().warning(f"Mixer init at {freq}Hz failed: {e}")

                PyUiLogger.get_logger().error("Failed to initialize pygame mixer at any frequency")
                return False

            except Exception as e:
                PyUiLogger.get_logger().warning(f"worker_init exception: {e}")
                return False

        def safe_load_sound(path):
            """Load a sound file (WAV)"""
            if path in sound_map:
                return sound_map[path]
            try:
                sound = pygame.mixer.Sound(path)
                sound_map[path] = sound
                return sound
            except Exception as e:
                PyUiLogger.get_logger().warning(f"Failed to load sound {path}: {e}")
                return None

        def stop_loop_internal():
            """Stop any looping audio"""
            nonlocal loop_channel, loop_music_path

            try:
                # Stop looping sound channel
                if loop_channel is not None:
                    pygame.mixer.Channel(loop_channel).stop()
                    loop_channel = None

                # Stop music
                if loop_music_path:
                    pygame.mixer.music.stop()
                    loop_music_path = None

            except Exception as e:
                PyUiLogger.get_logger().warning(f"stop_loop_internal exception: {e}")

        # Initialize audio
        init_ok = worker_init()
        PygameAudioPlayer._initialized = init_ok
        PygameAudioPlayer._init_failed = not init_ok

        # Main worker loop
        while PygameAudioPlayer._running:
            try:
                cmd: _Cmd = PygameAudioPlayer._cmd_q.get(timeout=0.2)
            except queue.Empty:
                continue

            try:
                name = cmd.name

                if name == "init":
                    reply_ok(cmd.resp_q, init_ok)

                elif name == "set_volume":
                    vol = cmd.args[0]
                    current_volume = vol
                    try:
                        # Set volume for all channels
                        for ch_idx in range(pygame.mixer.get_num_channels()):
                            pygame.mixer.Channel(ch_idx).set_volume(vol)
                        # Set music volume
                        pygame.mixer.music.set_volume(vol)
                    except Exception as e:
                        PyUiLogger.get_logger().warning(f"set_volume exception: {e}")
                    reply_ok(cmd.resp_q, True)

                elif name == "preload_wav":
                    path = cmd.args[0]
                    sound = safe_load_sound(path)
                    reply_ok(cmd.resp_q, sound is not None)

                elif name == "play_wav_once":
                    path = cmd.args[0]
                    sound = sound_map.get(path)
                    if not sound:
                        PyUiLogger.get_logger().warning(f"WAV {path} not preloaded")
                        reply_ok(cmd.resp_q, False)
                        continue

                    try:
                        sound.set_volume(current_volume)
                        sound.play()
                        reply_ok(cmd.resp_q, True)
                    except Exception as e:
                        PyUiLogger.get_logger().warning(f"play_wav_once exception: {e}")
                        reply_ok(cmd.resp_q, False)

                elif name == "start_loop_wav":
                    path = cmd.args[0]
                    stop_loop_internal()

                    sound = safe_load_sound(path)
                    if not sound:
                        reply_ok(cmd.resp_q, False)
                        continue

                    try:
                        sound.set_volume(current_volume)
                        # Play with infinite loop (-1)
                        channel = sound.play(loops=-1)
                        if channel:
                            loop_channel = channel
                            reply_ok(cmd.resp_q, True)
                        else:
                            PyUiLogger.get_logger().warning(f"Failed to get channel for loop WAV {path}")
                            reply_ok(cmd.resp_q, False)
                    except Exception as e:
                        PyUiLogger.get_logger().warning(f"start_loop_wav exception: {e}")
                        reply_ok(cmd.resp_q, False)

                elif name == "start_loop_music":
                    original_path = cmd.args[0]
                    stop_loop_internal()

                    # Convert MP3 to OGG if needed
                    safe_path = PygameAudioPlayer.mp3_to_safe_ogg(original_path)
                    if not safe_path:
                        # Try original if conversion failed
                        safe_path = original_path

                    try:
                        pygame.mixer.music.load(safe_path)
                        pygame.mixer.music.set_volume(current_volume)
                        pygame.mixer.music.play(loops=-1)  # Infinite loop
                        loop_music_path = safe_path
                        reply_ok(cmd.resp_q, True)
                    except Exception as e:
                        PyUiLogger.get_logger().warning(f"start_loop_music exception for {safe_path}: {e}")
                        reply_ok(cmd.resp_q, False)

                elif name == "stop_loop":
                    stop_loop_internal()
                    reply_ok(cmd.resp_q, True)

                elif name == "cleanup":
                    stop_loop_internal()

                    # Stop all sounds
                    try:
                        pygame.mixer.stop()
                        pygame.mixer.music.stop()
                    except Exception as e:
                        PyUiLogger.get_logger().warning(f"cleanup: stop exception: {e}")

                    # Clear sound cache
                    sound_map.clear()

                    # Quit mixer
                    try:
                        pygame.mixer.quit()
                    except Exception as e:
                        PyUiLogger.get_logger().warning(f"cleanup: quit exception: {e}")

                    # Stop worker
                    PygameAudioPlayer._running = False
                    reply_ok(cmd.resp_q, True)
                    break

                else:
                    PyUiLogger.get_logger().warning(f"Unknown worker command: {name}")
                    reply_ok(cmd.resp_q, False)

            except Exception as e:
                PyUiLogger.get_logger().warning(f"worker loop exception for cmd {cmd.name}: {e}")
                reply_ok(cmd.resp_q, False)

        # Final cleanup
        try:
            pygame.mixer.stop()
            pygame.mixer.music.stop()
            sound_map.clear()
            pygame.mixer.quit()
        except Exception:
            pass

        PyUiLogger.get_logger().info("PygameAudioPlayer worker exiting.")
