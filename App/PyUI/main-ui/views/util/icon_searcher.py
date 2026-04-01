class IconSearcher:
    __slots__ = ("rom_info", "get_icon_func")

    def __init__(self, rom_info, get_icon_func):
        self.rom_info = rom_info
        self.get_icon_func = get_icon_func

    def __call__(self, _):
        return self.get_icon_func(self.rom_info)