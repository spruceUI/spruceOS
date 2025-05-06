import json

class GameSystemConfig:
    def __init__(self, system_name):
        config_path = f"/mnt/SDCARD/Emu/{system_name}/config.json"
        with open(config_path, 'r', encoding='utf-8') as f:
            self._data = json.load(f)

    def get_label(self):
        return self._data.get('label')

    def get_icontop(self):
        return self._data.get('icontop')

    def get_icon(self):
        return self._data.get('icon')

    def get_icon_selected(self):
        return self._data.get('iconsel')

    def get_background(self):
        return self._data.get('background')

    def get_themecolor(self):
        return self._data.get('themecolor')

    def get_effectsh(self):
        return self._data.get('effectsh')

    def get_launch(self):
        return self._data.get('launch')

    def get_rompathlist(self):
        return self._data.get('rompathlist', [])

    def get_rompath(self):
        return self._data.get('rompath')

    def get_imgpath(self):
        return self._data.get('imgpath')

    def get_gamelist(self):
        return self._data.get('gamelist')

    def get_useswap(self):
        return self._data.get('useswap')

    def get_shortname(self):
        return self._data.get('shortname')

    def get_hidebios(self):
        return self._data.get('hidebios')

    def get_extlist(self):
        return self._data.get('extlist')

    def get_launchlist(self):
        return self._data.get('launchlist', [])
