from pathlib import Path
import subprocess
import sdl2
import sdl2.sdlmixer as sdlmixer
import threading
import queue
from typing import Optional
from utils.logger import PyUiLogger
from utils.time_logger import log_timing

# Commands for the worker
class _Cmd:
    def __init__(self, name, args=(), kwargs=None, resp_q: Optional[queue.Queue]=None):
        self.name = name
        self.args = args
        self.kwargs = kwargs or {}
        self.resp_q = resp_q

class Sdl2AudioPlayer:
    # Worker state
    _worker_thread: Optional[threading.Thread] = None
    _cmd_q: Optional[queue.Queue] = None
    _running = False

    # Public state
    _initialized = False
    _init_failed = False
    _current_volume = 128  # 0..128

    # Worker-owned resources (only touched by worker thread)
    # chunk_map: path -> Mix_Chunk pointer, music_map: path -> Mix_Music pointer
    # NOTE: these are stored and freed only in worker
    # (the main thread NEVER touches these pointers).
    # Worker owns lifecycle.
    @staticmethod
    def _ensure_worker():
        if Sdl2AudioPlayer._worker_thread and Sdl2AudioPlayer._running:
            return

        Sdl2AudioPlayer._cmd_q = queue.Queue()
        Sdl2AudioPlayer._running = True
        Sdl2AudioPlayer._worker_thread = threading.Thread(target=Sdl2AudioPlayer._worker_loop, daemon=True)
        Sdl2AudioPlayer._worker_thread.start()
        PyUiLogger.get_logger().info("Sdl2AudioPlayer worker thread started.")

    @staticmethod
    def _send_cmd(cmd_name, *args, expect_reply=False, **kwargs):
        Sdl2AudioPlayer._ensure_worker()
        resp_q = queue.Queue(maxsize=1) if expect_reply else None
        cmd = _Cmd(cmd_name, args=args, kwargs=kwargs, resp_q=resp_q)
        Sdl2AudioPlayer._cmd_q.put(cmd)
        if expect_reply:
            try:
                return resp_q.get(timeout=2.0)
            except queue.Empty:
                return None
        return None

    # Public API: these post commands to the worker and return immediately (or return result)
    @staticmethod
    def _init():
        with log_timing("SDL2 Audio initialization", PyUiLogger.get_logger()):    
            # Move init into worker; main thread asks worker to init
            res = Sdl2AudioPlayer._send_cmd("init", expect_reply=True)
            # res will be True/False or None on timeout
            if res is True:
                Sdl2AudioPlayer._initialized = True
                Sdl2AudioPlayer._init_failed = False
            else:
                Sdl2AudioPlayer._initialized = False
                Sdl2AudioPlayer._init_failed = True

    @staticmethod
    def audio_set_volume(volume: int):
        # Map 0..10 -> 0..128 as before
        vol = max(0, min(128, int(volume * 12.8)))
        Sdl2AudioPlayer._current_volume = vol
        Sdl2AudioPlayer._send_cmd("set_volume", vol)

    @staticmethod
    def audio_play_wav(file_path: str):
        Sdl2AudioPlayer._send_cmd("play_wav_once", file_path)

    @staticmethod
    def audio_loop_wav(file_path: str):
        # stops any existing loop and starts a new looping WAV
        Sdl2AudioPlayer._send_cmd("start_loop_wav", file_path)

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
                    "-y",                 # overwrite if partial exists
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
        Sdl2AudioPlayer._send_cmd("start_loop_music", file_path)

    @staticmethod
    def audio_stop_loop():
        Sdl2AudioPlayer._send_cmd("stop_loop")

    @staticmethod
    def audio_cleanup():
        # Request worker to cleanup and terminate; block until worker exits or timeout
        Sdl2AudioPlayer._send_cmd("cleanup")
        if Sdl2AudioPlayer._worker_thread:
            Sdl2AudioPlayer._worker_thread.join(timeout=3.0)
        Sdl2AudioPlayer._worker_thread = None
        Sdl2AudioPlayer._cmd_q = None
        Sdl2AudioPlayer._running = False
        Sdl2AudioPlayer._initialized = False
        Sdl2AudioPlayer._init_failed = False
        PyUiLogger.get_logger().info("Sdl2AudioPlayer cleaned up.")

    @staticmethod
    def load_wav(file_path: str):
        """Preload a WAV file into the worker's chunk_map."""
        return Sdl2AudioPlayer._send_cmd("preload_wav", file_path, expect_reply=True)
    
    # --------------------------
    # Worker implementation below
    # --------------------------
    @staticmethod
    def _worker_loop():
        """
        All SDL_mixer and SDL2 calls happen here ONLY.
        Commands come in through _cmd_q. Worker maintains its own maps.
        """
        chunk_map = {}  # path -> Mix_Chunk pointer
        music_map = {}  # path -> Mix_Music pointer
        loop_channel = None
        loop_music_path = None
        loop_chunk_path = None

        def reply_ok(resp_q, ok=True):
            if resp_q:
                try:
                    resp_q.put(ok, timeout=0.5)
                except Exception:
                    pass

        # Helper wrappers (worker-only)
        def worker_init():
            try:
                # check driver
                driver = sdl2.SDL_GetCurrentAudioDriver()
                if driver:
                    PyUiLogger.get_logger().info(f"Audio driver (pre-init): {driver.decode()}")
                else:
                    PyUiLogger.get_logger().warning("No SDL audio driver detected (pre-init).")

                if sdl2.SDL_InitSubSystem(sdl2.SDL_INIT_AUDIO) != 0:
                    PyUiLogger.get_logger().warning(f"SDL_InitSubSystem failed: {sdl2.SDL_GetError().decode()}")
                    return False

                # Try a few formats
                opened = False
                for freq, buf in [(44100, 1024), (22050, 1024), (16000, 512)]:
                    try:
                        if sdlmixer.Mix_OpenAudio(freq, sdl2.AUDIO_S16SYS, 2, buf) == 0:
                            PyUiLogger.get_logger().info(f"Mix_OpenAudio succeeded: {freq}@{buf}")
                            opened = True
                            break
                        else:
                            PyUiLogger.get_logger().warning(f"Mix_OpenAudio({freq}) failed: {sdlmixer.Mix_GetError().decode()}")
                    except Exception as e:
                        PyUiLogger.get_logger().warning(f"Mix_OpenAudio exception: {e}")
                if not opened:
                    return False
                sdlmixer.Mix_AllocateChannels(8)
                # set the initial volume
                sdlmixer.Mix_Volume(-1, Sdl2AudioPlayer._current_volume)
                sdlmixer.Mix_VolumeMusic(Sdl2AudioPlayer._current_volume)
                return True
            except Exception as e:
                PyUiLogger.get_logger().warning(f"worker_init exception: {e}")
                return False

        def safe_load_chunk(path):
            if path in chunk_map:
                return chunk_map[path]
            try:
                c = sdlmixer.Mix_LoadWAV(path.encode())
                if not c:
                    PyUiLogger.get_logger().warning(f"Mix_LoadWAV failed for {path}: {sdlmixer.Mix_GetError().decode()}")
                    return None
                chunk_map[path] = c
                return c
            except Exception as e:
                PyUiLogger.get_logger().warning(f"Mix_LoadWAV exception for {path}: {e}")
                return None

        def safe_load_music(path):
            if path in music_map:
                return music_map[path]
            try:
                m = sdlmixer.Mix_LoadMUS(path.encode())
                if not m:
                    PyUiLogger.get_logger().warning(f"Mix_LoadMUS failed for {path}: {sdlmixer.Mix_GetError().decode()}")
                    return None
                music_map[path] = m
                return m
            except Exception as e:
                PyUiLogger.get_logger().warning(f"Mix_LoadMUS exception for {path}: {e}")
                return None

        def stop_loop_internal():
            nonlocal loop_channel, loop_music_path, loop_chunk_path
            # Stop both music and chunk loop if present
            try:
                if loop_channel is not None:
                    sdlmixer.Mix_HaltChannel(loop_channel)
                if loop_music_path:
                    sdlmixer.Mix_HaltMusic()
            except Exception as e:
                PyUiLogger.get_logger().warning(f"stop_loop_internal: Mix_Halt exception: {e}")

            # Wait for channels to settle
            for _ in range(50):
                # check playing channel (if any)
                try:
                    playing = sdlmixer.Mix_Playing(loop_channel) if loop_channel is not None else 0
                except Exception:
                    playing = 0
                if not playing:
                    break
                sdl2.SDL_Delay(10)

            # do NOT free chunk/music here if you want to be extra-safe.
            # We'll free in cleanup() below.
            loop_channel = None
            loop_music_path = None
            loop_chunk_path = None

        # Initialize audio now (worker does the actual init)
        init_ok = worker_init()
        # post result to main via shared flags
        Sdl2AudioPlayer._initialized = init_ok
        Sdl2AudioPlayer._init_failed = not init_ok

        # main worker loop
        while Sdl2AudioPlayer._running:
            try:
                cmd: _Cmd = Sdl2AudioPlayer._cmd_q.get(timeout=0.2)
            except queue.Empty:
                # nothing to do; allow loop to continue and react to running state
                continue

            try:
                name = cmd.name
                if name == "init":
                    reply_ok(cmd.resp_q, init_ok)
                elif name == "set_volume":
                    vol = cmd.args[0]
                    try:
                        sdlmixer.Mix_Volume(-1, vol)
                        sdlmixer.Mix_VolumeMusic(vol)
                    except Exception as e:
                        PyUiLogger.get_logger().warning(f"set_volume exception: {e}")
                    reply_ok(cmd.resp_q, True)
                elif name == "preload_wav":
                    path = cmd.args[0]
                    if path in chunk_map:
                        reply_ok(cmd.resp_q, True)
                        continue
                    try:
                        c = sdlmixer.Mix_LoadWAV(path.encode())
                        if not c:
                            PyUiLogger.get_logger().warning(f"preload_wav: Mix_LoadWAV failed for {path}: {sdlmixer.Mix_GetError().decode()}")
                            reply_ok(cmd.resp_q, False)
                            continue
                        chunk_map[path] = c
                        PyUiLogger.get_logger().info(f"preload_wav: {path} loaded successfully")
                        reply_ok(cmd.resp_q, True)
                    except Exception as e:
                        PyUiLogger.get_logger().warning(f"preload_wav exception for {path}: {e}")
                        reply_ok(cmd.resp_q, False)
                elif name == "play_wav_once":
                    path = cmd.args[0]
                    c = chunk_map.get(path)
                    if not c:
                        PyUiLogger.get_logger().warning(f"WAV {path} not preloaded, cannot play safely while MP3 is active")
                        reply_ok(cmd.resp_q, False)
                        continue

                    try:
                        sdlmixer.Mix_VolumeChunk(c, Sdl2AudioPlayer._current_volume)
                        ch = sdlmixer.Mix_PlayChannel(-1, c, 0)
                        if ch == -1:
                            PyUiLogger.get_logger().warning(f"Mix_PlayChannel failed for {path}: {sdlmixer.Mix_GetError().decode()}")
                            reply_ok(cmd.resp_q, False)
                            continue
                        reply_ok(cmd.resp_q, True)
                    except Exception as e:
                        PyUiLogger.get_logger().warning(f"play_wav_once exception: {e}")
                        reply_ok(cmd.resp_q, False)
                elif name == "start_loop_wav":
                    path = cmd.args[0]
                    # stop any existing loop
                    stop_loop_internal()
                    c = safe_load_chunk(path)
                    if not c:
                        reply_ok(cmd.resp_q, False)
                        continue
                    try:
                        sdlmixer.Mix_VolumeChunk(c, Sdl2AudioPlayer._current_volume)
                        ch = sdlmixer.Mix_PlayChannel(-1, c, -1)
                        if ch == -1:
                            PyUiLogger.get_logger().warning(f"start_loop_wav: Mix_PlayChannel failed for {path}: {sdlmixer.Mix_GetError().decode()}")
                            reply_ok(cmd.resp_q, False)
                            continue
                        loop_channel = ch
                        loop_chunk_path = path
                        reply_ok(cmd.resp_q, True)
                    except Exception as e:
                        PyUiLogger.get_logger().warning(f"start_loop_wav exception: {e}")
                        reply_ok(cmd.resp_q, False)
                elif name == "start_loop_music":
                    original_path = cmd.args[0]

                    # Stop anything currently playing
                    stop_loop_internal()

                    # Convert MP3 → OGG (or reuse cached)
                    safe_path = Sdl2AudioPlayer.mp3_to_safe_ogg(original_path)
                    if not safe_path:
                        PyUiLogger.get_logger().warning(
                            f"start_loop_music: could not obtain safe audio for {original_path}"
                        )
                        reply_ok(cmd.resp_q, False)
                        continue

                    # Load ONLY the safe format
                    m = safe_load_music(safe_path)
                    if not m:
                        reply_ok(cmd.resp_q, False)
                        continue

                    try:
                        sdlmixer.Mix_VolumeMusic(Sdl2AudioPlayer._current_volume)
                        if sdlmixer.Mix_PlayMusic(m, -1) == -1:
                            PyUiLogger.get_logger().warning(
                                f"Mix_PlayMusic failed for {safe_path}: {sdlmixer.Mix_GetError().decode()}"
                            )
                            reply_ok(cmd.resp_q, False)
                            continue

                        loop_music_path = safe_path
                        reply_ok(cmd.resp_q, True)

                    except Exception as e:
                        PyUiLogger.get_logger().warning(f"start_loop_music exception: {e}")
                        reply_ok(cmd.resp_q, False)
                elif name == "stop_loop":
                    stop_loop_internal()
                    reply_ok(cmd.resp_q, True)
                elif name == "cleanup":
                    # stop loops
                    stop_loop_internal()
                    # halt everything and wait a bit
                    try:
                        sdlmixer.Mix_HaltChannel(-1)
                        sdlmixer.Mix_HaltMusic()
                    except Exception as e:
                        PyUiLogger.get_logger().warning(f"cleanup: halt exception: {e}")
                    sdl2.SDL_Delay(80)
                    # free all chunks and musics safely
                    for p, cptr in list(chunk_map.items()):
                        try:
                            sdlmixer.Mix_FreeChunk(cptr)
                        except Exception as e:
                            PyUiLogger.get_logger().warning(f"cleanup: Mix_FreeChunk exception for {p}: {e}")
                        finally:
                            chunk_map.pop(p, None)
                    for p, mptr in list(music_map.items()):
                        try:
                            sdlmixer.Mix_FreeMusic(mptr)
                        except Exception as e:
                            PyUiLogger.get_logger().warning(f"cleanup: Mix_FreeMusic exception for {p}: {e}")
                        finally:
                            music_map.pop(p, None)
                    # close audio
                    try:
                        sdlmixer.Mix_CloseAudio()
                    except Exception as e:
                        PyUiLogger.get_logger().warning(f"cleanup: Mix_CloseAudio exception: {e}")
                    try:
                        sdl2.SDL_QuitSubSystem(sdl2.SDL_INIT_AUDIO)
                    except Exception:
                        pass
                    # stop worker
                    Sdl2AudioPlayer._running = False
                    reply_ok(cmd.resp_q, True)
                    # break out after replying
                    break
                else:
                    PyUiLogger.get_logger().warning(f"Unknown worker command: {name}")
                    reply_ok(cmd.resp_q, False)
            except Exception as e:
                PyUiLogger.get_logger().warning(f"worker loop exception for cmd {cmd.name}: {e}")
                reply_ok(cmd.resp_q, False)

        # ensure final cleanup (if any left)
        try:
            # best-effort free leftover
            for p, cptr in list(chunk_map.items()):
                try:
                    sdlmixer.Mix_FreeChunk(cptr)
                except Exception:
                    pass
                chunk_map.pop(p, None)
            for p, mptr in list(music_map.items()):
                try:
                    sdlmixer.Mix_FreeMusic(mptr)
                except Exception:
                    pass
                music_map.pop(p, None)
            try:
                sdlmixer.Mix_CloseAudio()
            except Exception:
                pass
            try:
                sdl2.SDL_QuitSubSystem(sdl2.SDL_INIT_AUDIO)
            except Exception:
                pass
        except Exception:
            pass

        PyUiLogger.get_logger().info("Sdl2AudioPlayer worker exiting.")
