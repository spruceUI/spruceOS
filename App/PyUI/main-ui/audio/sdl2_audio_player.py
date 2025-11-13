import sdl2
import sdl2.sdlmixer as sdlmixer
import threading
import sys
import time
from utils.logger import PyUiLogger

class Sdl2AudioPlayer:
    _initialized = False
    _init_failed = False
    _loop_thread = None
    _stop_loop = False
    _current_volume = 128  # max volume by default

    @staticmethod
    def _init():
        if Sdl2AudioPlayer._initialized:
            return

        PyUiLogger.get_logger().info("Initializing audio system...")
        if sdl2.SDL_InitSubSystem(sdl2.SDL_INIT_AUDIO) != 0:
            PyUiLogger.get_logger().warning(
                f"Failed to init SDL audio subsystem: {sdl2.SDL_GetError().decode()}"
            )
            Sdl2AudioPlayer._init_failed = True
            return

        if sdlmixer.Mix_OpenAudio(44100, sdl2.AUDIO_S16SYS, 2, 1024) != 0:
            PyUiLogger.get_logger().warning(
                f"Failed to open audio device: {sdlmixer.Mix_GetError().decode()}"
            )
            Sdl2AudioPlayer._init_failed = True
            return

        sdlmixer.Mix_AllocateChannels(8)
        Sdl2AudioPlayer._initialized = True
        PyUiLogger.get_logger().info("Audio system initialized successfully.")

    @staticmethod
    def audio_set_volume(volume: int):
        """
        Sets the playback volume in real-time.
        volume: 0 (silent) to 10 (max)
        """
        Sdl2AudioPlayer._current_volume = max(0, min(128, int(volume * 12.8)))

        # Apply volume to all active WAV channels (-1)
        sdlmixer.Mix_Volume(-1, Sdl2AudioPlayer._current_volume)

        # Apply volume to music (MP3/OGG)
        sdlmixer.Mix_VolumeMusic(Sdl2AudioPlayer._current_volume)

        PyUiLogger.get_logger().info(
            f"Volume set to {Sdl2AudioPlayer._current_volume}/128"
        )


    @staticmethod
    def audio_play_wav(file_path: str):
        """Plays the WAV file once (blocking)."""
        #PyUiLogger.get_logger().info(f"Playing {file_path}")
        if(not Sdl2AudioPlayer._init_failed):
            Sdl2AudioPlayer._init()
            sound = sdlmixer.Mix_LoadWAV(file_path.encode())
            if not sound:
                PyUiLogger.get_logger().warning(
                    f"Failed to load WAV: {file_path}, SDL_mixer error: {sdlmixer.Mix_GetError().decode()}"
                )
                return

            # Apply current volume to this chunk
            sdlmixer.Mix_VolumeChunk(sound, Sdl2AudioPlayer._current_volume)

            channel = sdlmixer.Mix_PlayChannel(-1, sound, 0)
            if channel == -1:
                PyUiLogger.get_logger().warning(
                    f"Failed to play WAV: {file_path}, SDL_mixer error: {sdlmixer.Mix_GetError().decode()}"
                )
                sdlmixer.Mix_FreeChunk(sound)
                return

            while sdlmixer.Mix_Playing(channel) != 0:
                sdl2.SDL_Delay(50)

            sdlmixer.Mix_FreeChunk(sound)

    @staticmethod
    def audio_loop_wav(file_path: str):
        #PyUiLogger.get_logger().info(f"Looping {file_path}")
        if(not Sdl2AudioPlayer._init_failed):

            def loop():
                sound = sdlmixer.Mix_LoadWAV(file_path.encode())
                if not sound:
                    PyUiLogger.get_logger().warning(
                        f"Failed to load WAV: {file_path}, SDL_mixer error: {sdlmixer.Mix_GetError().decode()}"
                    )
                    return

                # Apply current volume to this chunk
                sdlmixer.Mix_VolumeChunk(sound, Sdl2AudioPlayer._current_volume)

                channel = sdlmixer.Mix_PlayChannel(-1, sound, -1)  # -1 = loop forever
                if channel == -1:
                    PyUiLogger.get_logger().warning(
                        f"Failed to play WAV: {file_path}, SDL_mixer error: {sdlmixer.Mix_GetError().decode()}"
                    )
                    sdlmixer.Mix_FreeChunk(sound)
                    return

                while not Sdl2AudioPlayer._stop_loop:
                    sdl2.SDL_Delay(50)

                sdlmixer.Mix_HaltChannel(channel)
                sdlmixer.Mix_FreeChunk(sound)

            Sdl2AudioPlayer._init()
            Sdl2AudioPlayer._stop_loop = False
            Sdl2AudioPlayer._loop_thread = threading.Thread(target=loop, daemon=True)
            Sdl2AudioPlayer._loop_thread.start()

    @staticmethod
    def audio_loop_mp3(file_path: str):
        """Loops an MP3 file until stop_loop is called (non-blocking)."""
        #PyUiLogger.get_logger().info(f"Looping MP3 {file_path}")
        if(not Sdl2AudioPlayer._init_failed):

            def loop():
                music = sdlmixer.Mix_LoadMUS(file_path.encode())
                if not music:
                    PyUiLogger.get_logger().warning(
                        f"Failed to load MP3: {file_path}, SDL_mixer error: {sdlmixer.Mix_GetError().decode()}"
                    )
                    return

                # Set initial volume
                sdlmixer.Mix_VolumeMusic(Sdl2AudioPlayer._current_volume)

                if sdlmixer.Mix_PlayMusic(music, -1) == -1:  # -1 = loop forever
                    PyUiLogger.get_logger().warning(
                        f"Failed to play MP3: {file_path}, SDL_mixer error: {sdlmixer.Mix_GetError().decode()}"
                    )
                    sdlmixer.Mix_FreeMusic(music)
                    return

                # Keep the thread alive until stop is requested
                while not Sdl2AudioPlayer._stop_loop:
                    sdl2.SDL_Delay(50)

                sdlmixer.Mix_HaltMusic()
                sdlmixer.Mix_FreeMusic(music)

            Sdl2AudioPlayer._init()
            Sdl2AudioPlayer._stop_loop = False
            Sdl2AudioPlayer._loop_thread = threading.Thread(target=loop, daemon=True)
            Sdl2AudioPlayer._loop_thread.start()


    @staticmethod
    def audio_stop_loop():
        """Stops the looping WAV playback."""
        Sdl2AudioPlayer._stop_loop = True
        if Sdl2AudioPlayer._loop_thread:
            Sdl2AudioPlayer._loop_thread.join()
            Sdl2AudioPlayer._loop_thread = None

    @staticmethod
    def audio_cleanup():
        Sdl2AudioPlayer.audio_stop_loop()
        if Sdl2AudioPlayer._initialized:
            sdlmixer.Mix_CloseAudio()
            sdl2.SDL_Quit()
            Sdl2AudioPlayer._initialized = False
