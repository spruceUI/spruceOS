
from audio.sdl2_audio_player import Sdl2AudioPlayer


class AudioPlayerDelegateSdl2:

    def __init__(self):
        pass

    def audio_set_volume(self,volume: int):
        Sdl2AudioPlayer.audio_set_volume(volume)
        
    def audio_play_wav(self,file_path: str):
        Sdl2AudioPlayer.audio_play_wav(file_path)

    def audio_loop_wav(self,file_path: str):
        Sdl2AudioPlayer.audio_loop_wav(file_path)

    def audio_loop_mp3(self,file_path: str):
        Sdl2AudioPlayer.audio_loop_mp3(file_path)

    def audio_stop_loop(self):
        Sdl2AudioPlayer.audio_stop_loop()

    def load_wav(self,file_path: str):
        Sdl2AudioPlayer.load_wav(file_path)
