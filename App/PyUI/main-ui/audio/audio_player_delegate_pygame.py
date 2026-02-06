"""
Pygame audio player delegate
Provides the same interface as audio_player_delegate_sdl2.py but uses pygame
"""

from audio.pygame_audio_player import PygameAudioPlayer


class AudioPlayerDelegatePygame:

    def __init__(self):
        pass

    def audio_set_volume(self, volume: int):
        PygameAudioPlayer.audio_set_volume(volume)

    def audio_play_wav(self, file_path: str):
        PygameAudioPlayer.audio_play_wav(file_path)

    def audio_loop_wav(self, file_path: str):
        PygameAudioPlayer.audio_loop_wav(file_path)

    def audio_loop_mp3(self, file_path: str):
        PygameAudioPlayer.audio_loop_mp3(file_path)

    def audio_stop_loop(self):
        PygameAudioPlayer.audio_stop_loop()

    def load_wav(self, file_path: str):
        PygameAudioPlayer.load_wav(file_path)
