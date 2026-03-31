class ImageSearcher:
    __slots__ = ("rom_info", "game_entry", "prefer_savestate", "get_image_path_func")

    def __init__(self, rom_info, game_entry, prefer_savestate, get_image_path_func):
        self.rom_info = rom_info
        self.game_entry = game_entry
        self.prefer_savestate = prefer_savestate
        self.get_image_path_func = get_image_path_func

    def __call__(self, _):
        return self.get_image_path_func(self.rom_info, self.game_entry, self.prefer_savestate)