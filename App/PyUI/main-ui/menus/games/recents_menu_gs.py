
import re
from typing import List
from devices.device import Device
from display.resize_type import ResizeType
from menus.games.recents_menu import RecentsMenu
from menus.games.utils.recents_manager import RecentsManager
from menus.games.utils.rom_file_name_utils import RomFileNameUtils
from menus.games.utils.rom_info import RomInfo
from menus.games.utils.rom_select_options_builder import get_rom_select_options_builder
from themes.theme import Theme
from utils.consts import GAME_SWITCHER


class RecentsMenuGS(RecentsMenu):
    _game_release_years = {
        "earthwormjim": 1994,
        "earthwormjim2": 1995,
        "eccojr": 1995,
        "eccothedolphin": 1992,
        "legendofzeldatheoracleofages": 2001,
        "legendofzeldatheoracleofseasons": 2001,
        "sonic2knuckles": 1994,
        "sonic3knuckles": 1994,
        "sonicandknucklessonicthehedgehog2": 1994,
        "sonicandknucklessonicthehedgehog3": 1994,
        "sonicknucklessonicthehedgehog2": 1994,
        "sonicknucklessonicthehedgehog3": 1994,
        "sonicthehedgehog": 1991,
        "sonicthehedgehog2": 1992,
        "sonicthehedgehog3": 1994,
        "supermarioworld": 1990,
        "supermetroid": 1994,
        "thelegendofzeldaoracleofages": 2001,
        "thelegendofzeldaoracleofseasons": 2001,
    }

    def __init__(self):
        super().__init__()


    def run_rom_selection(self) :
        return self._run_rom_selection("Game Switcher")

    def get_amount_of_recents_to_allow(self):
        return Device.get_device().get_system_config().game_switcher_game_count()

    def default_to_last_game_selection(self):
        return False

    def prefer_savestate_screenshot(self):
        return Device.get_device().get_system_config().use_savestate_screenshots(GAME_SWITCHER)

    def _clean_display_name(self, display_name):
        display_name = str(display_name or "").replace("_", " ")
        display_name = re.sub(r"\s*[\(\[].*?[\)\]]", "", display_name)
        display_name = re.sub(r"\s+", " ", display_name).strip(" -")

        article_match = re.match(r"^(.+),\s+(The|A|An)(\b.*)$", display_name, re.IGNORECASE)
        if article_match:
            display_name = f"{article_match.group(2)} {article_match.group(1)}{article_match.group(3)}"

        if display_name.isupper():
            display_name = display_name.title()

        return display_name

    def _release_year_key(self, display_name):
        display_name = self._clean_display_name(display_name)
        display_name = display_name.replace("&", " ").replace("+", " ")
        return re.sub(r"[^a-z0-9]", "", display_name.lower())

    def _get_game_release_year(self, rom_info, display_name):
        raw_file_name = RomFileNameUtils.get_rom_name_without_extensions(
            rom_info.game_system,
            rom_info.rom_file_path
        )
        for candidate in (display_name, rom_info.display_name, raw_file_name):
            year = self._game_release_years.get(self._release_year_key(candidate))
            if year is not None:
                return year
        return None

    def _get_compact_description(self, rom_info, display_name):
        description = rom_info.game_system.display_name
        year = self._get_game_release_year(rom_info, display_name)
        if year is not None:
            description = f"{description} - {year}"
        return description

    def _get_rom_list(self):
        rom_list = super()._get_rom_list()

        image_builder = get_rom_select_options_builder()
        for entry in rom_list:
            rom_info = entry.get_value()
            display_name = rom_info.display_name
            if display_name is None:
                display_name = RomFileNameUtils.get_rom_name_without_extensions(
                    rom_info.game_system,
                    rom_info.rom_file_path
                )
            display_name = self._clean_display_name(display_name)

            entry.primary_text = display_name
            entry.primary_text_long = display_name
            entry._description = self._get_compact_description(rom_info, display_name)
            entry._description_func = None

            extra_data = entry.get_extra_data() or {}
            extra_data["compact_text_overlay"] = True

            if self.prefer_savestate_screenshot():
                box_art_path = image_builder.get_image_path(
                    rom_info,
                    prefer_savestate_screenshot=False
                )
                if box_art_path is not None and box_art_path != entry.get_image_path():
                    extra_data["overlay_image_path"] = box_art_path

            entry.extra_data = extra_data

        return rom_list

    def get_rom_list(self) -> List[RomInfo]:
        return RecentsManager.get_recents()

    def get_view_type(self):
        return Theme.get_view_type_for_game_switcher()

    def full_screen_grid_resize_type(self):
        return Theme.get_resize_type_for_game_switcher()

    def get_set_top_bar_text_to_game_selection(self):
        return Theme.get_set_top_bar_text_to_game_selection_for_game_switcher()

    def get_image_resize_height_multiplier(self):
        if(ResizeType.ZOOM == Theme.get_resize_type_for_game_switcher() and Theme.true_full_screen_game_switcher()):
            return 1.0
        else:
            return None
