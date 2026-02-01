

class GameEntry:
    def __init__(self, label, launch, rom_path, type):
        self._label = label
        self._launch = launch
        self._rom_path = rom_path
        self._type = type
    
    @property
    def label(self):
        return self._label
    
    @property
    def launch(self):
        return self._launch
    
    @property
    def rom_path(self):
        return self._rom_path
    
    @property
    def type(self):
        return self._type
    