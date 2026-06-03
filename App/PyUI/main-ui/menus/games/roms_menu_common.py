
import os
import re
import subprocess
import time
from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from menus.games.game_config_menu import GameConfigMenu
from menus.games.game_select_menu_popup import GameSelectMenuPopup
from menus.games.in_game_menu_listener import InGameMenuListener
from menus.games.utils.collections_manager import CollectionsManager
from menus.games.utils.favorites_manager import FavoritesManager
from menus.games.utils.recents_manager import RecentsManager
from menus.games.utils.rom_file_name_utils import RomFileNameUtils
from menus.games.utils.rom_info import RomInfo
from menus.games.utils.rom_select_options_builder import get_rom_select_options_builder
from themes.theme import Theme
from utils.activity.activity_log import ActivityLog
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from utils.py_ui_state import PyUiState
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from abc import ABC, abstractmethod

from views.view_creator import ViewCreator
from views.view_type import ViewType


class RomsMenuCommon(ABC):
    _activity_log_cache_mtime = None
    _activity_log_cache_path = None
    _activity_runtime_cache = {}

    _game_release_years = {
        "chronotrigger": 1995,
        "donkeykongcountry": 1994,
        "donkeykongcountry2diddyskongquest": 1995,
        "earthwormjim": 1994,
        "earthwormjim2": 1995,
        "earthbound": 1994,
        "eccojr": 1995,
        "eccothedolphin": 1992,
        "gunstarheroes": 1993,
        "gunstarsuperheroes": 2005,
        "kirbynightmareindreamland": 2002,
        "legendofzeldaalinktothepast": 1991,
        "legendofzeldatheoracleofages": 2001,
        "legendofzeldatheoracleofseasons": 2001,
        "metroidfusion": 2002,
        "metroidzeromission": 2004,
        "sonic2knuckles": 1994,
        "sonic3knuckles": 1994,
        "sonicandknucklessonicthehedgehog2": 1994,
        "sonicandknucklessonicthehedgehog3": 1994,
        "sonicknucklessonicthehedgehog2": 1994,
        "sonicknucklessonicthehedgehog3": 1994,
        "sonicthehedgehog": 1991,
        "sonicthehedgehog2": 1992,
        "sonicthehedgehog3": 1994,
        "supermarioadvance": 2001,
        "supermarioadvance2supermarioworld": 2001,
        "supermarioadvance3yoshisisland": 2002,
        "supermarioadvance4supermariobros3": 2003,
        "supermariobrosdeluxe": 1999,
        "supermarioland": 1989,
        "supermarioland26goldencoins": 1992,
        "supermarioworld": 1990,
        "supermarioworld2yoshisisland": 1995,
        "supermetroid": 1994,
        "thelegendofzeldaoracleofages": 2001,
        "thelegendofzeldaoracleofseasons": 2001,
        "thelegendofzeldaalinktothepast": 1991,
        "vectorman": 1995,
        "vectorman2": 1996,
    }

    _game_hltb_times = {
        "chronotrigger": "23h",
        "donkeykongcountry": "4h",
        "donkeykongcountry2diddyskongquest": "5.5h",
        "earthbound": "28h",
        "earthwormjim": "2.5h",
        "earthwormjim2": "3h",
        "eccojr": "1h",
        "eccothedolphin": "4h",
        "gunstarheroes": "1.5h",
        "gunstarsuperheroes": "2.5h",
        "kirbynightmareindreamland": "2.5h",
        "legendofzeldaalinktothepast": "15h",
        "legendofzeldatheoracleofages": "16h",
        "legendofzeldatheoracleofseasons": "15h",
        "metroidfusion": "5h",
        "metroidzeromission": "4.5h",
        "sonic2knuckles": "2.5h",
        "sonic3knuckles": "4h",
        "sonicandknucklessonicthehedgehog2": "2.5h",
        "sonicandknucklessonicthehedgehog3": "4h",
        "sonicknucklessonicthehedgehog2": "2.5h",
        "sonicknucklessonicthehedgehog3": "4h",
        "sonicthehedgehog": "2h",
        "sonicthehedgehog2": "2.5h",
        "sonicthehedgehog3": "3h",
        "supermarioadvance": "2.5h",
        "supermarioadvance2supermarioworld": "5h",
        "supermarioadvance3yoshisisland": "8h",
        "supermarioadvance4supermariobros3": "4h",
        "supermariobrosdeluxe": "3h",
        "supermarioland": "1h",
        "supermarioland26goldencoins": "2h",
        "supermarioworld": "5h",
        "supermarioworld2yoshisisland": "8h",
        "supermetroid": "7.5h",
        "thelegendofzeldaalinktothepast": "15h",
        "thelegendofzeldaoracleofages": "16h",
        "thelegendofzeldaoracleofseasons": "15h",
        "vectorman": "2h",
        "vectorman2": "2h",
    }

    def __init__(self, ):
        self.in_game_menu_listener = InGameMenuListener()
        self.popup_menu = GameSelectMenuPopup()

        self.support_only_game_launching = Device.get_device().get_system_config().game_selection_only_mode_enabled()

    def _remove_extension(self,file_name):
        return os.path.splitext(file_name)[0]

    def _get_image_path(self, rom_path):
        # Get the base filename without extension (e.g., "DKC")
        return get_rom_select_options_builder().get_image_path(rom_path, prefer_savestate_screenshot=self.prefer_savestate_screenshot())

    def _extract_game_system(self, rom_path):
        rom_path = os.path.abspath(os.path.normpath(rom_path))
        parts = os.path.normpath(rom_path).split(os.sep)
        try:
            roms_index = [p.lower() for p in parts].index("roms")
            return parts[roms_index + 1]
        except (ValueError, IndexError) as e:
            PyUiLogger.get_logger().error(f"Error extracting subdirectory after 'Roms' for {rom_path}: {e}")
        return None  # "Roms" not found or no subdirectory after it

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

    def _get_howlongtobeat_time(self, rom_info, display_name):
        raw_file_name = RomFileNameUtils.get_rom_name_without_extensions(
            rom_info.game_system,
            rom_info.rom_file_path
        )
        for candidate in (display_name, rom_info.display_name, raw_file_name):
            hltb_time = self._game_hltb_times.get(self._release_year_key(candidate))
            if hltb_time is not None:
                return hltb_time
        return None

    def _get_activity_runtimes(self):
        activity_log_path = PyUiConfig.get_activity_log_path()
        if activity_log_path is None or not os.path.exists(activity_log_path):
            return {}

        try:
            activity_log_mtime = os.path.getmtime(activity_log_path)
        except OSError:
            return {}

        if (
            RomsMenuCommon._activity_log_cache_path == activity_log_path
            and RomsMenuCommon._activity_log_cache_mtime == activity_log_mtime
        ):
            return RomsMenuCommon._activity_runtime_cache

        try:
            runtimes = ActivityLog(activity_log_path).all_apps_all_time()
        except Exception as e:
            PyUiLogger.get_logger().warning(f"Failed to load activity log: {e}")
            runtimes = {}

        RomsMenuCommon._activity_log_cache_path = activity_log_path
        RomsMenuCommon._activity_log_cache_mtime = activity_log_mtime
        RomsMenuCommon._activity_runtime_cache = runtimes
        return runtimes

    def _get_activity_key(self, rom_info):
        parts = os.path.normpath(rom_info.rom_file_path).split(os.sep)
        lowered_parts = [part.lower() for part in parts]
        try:
            roms_index = lowered_parts.index("roms")
        except ValueError:
            return None
        return "/".join(parts[roms_index:])

    def _get_hltb_seconds(self, hltb_time):
        if hltb_time is None:
            return None

        hltb_time = str(hltb_time).strip().lower()
        match = re.match(r"^(\d+(?:\.\d+)?)\s*h$", hltb_time)
        if match:
            return int(float(match.group(1)) * 3600)

        match = re.match(r"^(\d+(?:\.\d+)?)\s*m$", hltb_time)
        if match:
            return int(float(match.group(1)) * 60)

        return None

    def _format_playtime(self, seconds):
        seconds = max(0, int(seconds or 0))
        minutes = int(round(seconds / 60))
        if seconds > 0:
            minutes = max(1, minutes)

        hours = minutes // 60
        minutes = minutes % 60
        if hours > 0 and minutes > 0:
            return f"{hours}h {minutes}m"
        if hours > 0:
            return f"{hours}h"
        return f"{minutes}m"

    def _get_playtime_progress(self, rom_info, hltb_time):
        hltb_seconds = self._get_hltb_seconds(hltb_time)
        if hltb_seconds is None or hltb_seconds <= 0:
            return None

        activity_key = self._get_activity_key(rom_info)
        if activity_key is None:
            return None

        played_seconds = self._get_activity_runtimes().get(activity_key, 0)
        remaining_seconds = max(0, hltb_seconds - played_seconds)
        progress_percent = min(100, int(round((played_seconds / hltb_seconds) * 100)))

        return {
            "played_time_label": self._format_playtime(played_seconds),
            "remaining_time_label": self._format_playtime(remaining_seconds),
            "playtime_progress_percent": progress_percent,
        }

    def _get_compact_description(self, rom_info, display_name):
        description_parts = [rom_info.game_system.display_name]
        year = self._get_game_release_year(rom_info, display_name)
        if year is not None:
            description_parts.append(str(year))
        return " - ".join(description_parts)

    def _get_save_state_preview_path(self, rom_info):
        preview_path = Device.get_device().get_save_state_image(rom_info)
        if preview_path is not None and os.path.exists(preview_path):
            return preview_path
        return None

    def _prepare_hot_switcher_carousel_rom_list(self, rom_list):
        image_builder = get_rom_select_options_builder()
        for entry in rom_list:
            rom_info = entry.get_value()
            if rom_info is None or getattr(rom_info, "is_collection", False):
                continue

            display_name = entry.get_primary_text_long()
            if display_name is None:
                display_name = entry.get_primary_text()
            display_name = self._clean_display_name(display_name)

            preview_path = self._get_save_state_preview_path(rom_info)
            box_art_path = image_builder.get_image_path(
                rom_info,
                prefer_savestate_screenshot=False
            )
            if box_art_path == preview_path:
                box_art_path = None

            if box_art_path is not None:
                entry.image_path = box_art_path
                entry.image_path_selected = box_art_path
                entry.image_path_searcher = None
                entry.image_path_selected_searcher = None

            entry.primary_text = display_name
            entry.primary_text_long = display_name
            entry._description = self._get_compact_description(rom_info, display_name)
            entry._description_func = None
            hltb_time = self._get_howlongtobeat_time(rom_info, display_name)
            playtime_progress = self._get_playtime_progress(rom_info, hltb_time)

            extra_data = entry.get_extra_data() or {}
            extra_data["compact_text_overlay"] = True
            if hltb_time is not None:
                extra_data["hltb_time"] = hltb_time
            else:
                extra_data.pop("hltb_time", None)

            if playtime_progress is not None:
                extra_data.update(playtime_progress)
            else:
                extra_data.pop("played_time_label", None)
                extra_data.pop("remaining_time_label", None)
                extra_data.pop("playtime_progress_percent", None)

            if box_art_path is not None:
                extra_data["box_art_image_path"] = box_art_path
            else:
                extra_data.pop("box_art_image_path", None)

            if preview_path is not None:
                extra_data["preview_image_path"] = preview_path
            else:
                extra_data.pop("preview_image_path", None)

            entry.extra_data = extra_data

        return rom_list

    def _carousel_entry_is_favorite(self, entry):
        rom_info = entry.get_value()
        if rom_info is None or getattr(rom_info, "is_collection", False):
            return False
        return FavoritesManager.is_favorite(rom_info)

    def _get_view_rom_list(self, rom_list):
        if self.get_view_type() != ViewType.CAROUSEL:
            return rom_list

        favorite_roms = [
            entry for entry in rom_list
            if self._carousel_entry_is_favorite(entry)
        ]
        return self._prepare_hot_switcher_carousel_rom_list(favorite_roms)

    def _get_view_selection(self, selected, source_rom_list, view_rom_list):
        if len(view_rom_list) == 0:
            return Selection(None, None, 0)

        selected_entry = selected.get_selection()
        if selected_entry is None and 0 <= selected.get_index() < len(source_rom_list):
            selected_entry = source_rom_list[selected.get_index()]

        if selected_entry is not None:
            for index, entry in enumerate(view_rom_list):
                if entry == selected_entry:
                    return Selection(None, None, index)

        return Selection(None, None, min(selected.get_index(), len(view_rom_list) - 1))

    @abstractmethod
    def _get_rom_list(self) -> list[GridOrListEntry]:
        pass

    def _run_subfolder_menu(self, rom_info : RomInfo) -> list[GridOrListEntry]:
        from menus.games.game_select_menu import GameSelectMenu
        return GameSelectMenu().run_rom_selection(rom_info.game_system, rom_info.rom_file_path)


    def _load_collection_menu(self, rom_info : RomInfo) -> list[GridOrListEntry]:
        self.current_collection = rom_info.rom_file_path
        PyUiState.set_in_game_selection_screen(True)
        rom_list = self.build_rom_selection_for_collection(self.current_collection)
        while(ControllerInput.B != self._run_rom_selection_for_rom_list(self.current_collection, rom_list)):
            pass

        PyUiState.set_in_game_selection_screen(False)
        self.current_collection = None

    def build_rom_selection_for_collection(self, collection):
        raw_rom_list = CollectionsManager.get_games_in_collection(collection)

        rom_list = []

        for rom_info in raw_rom_list:
            rom_file_name = RomFileNameUtils.get_rom_name_without_extensions(rom_info.game_system, rom_info.rom_file_path)
            img_path = self._get_image_path(rom_info)
            rom_list.append(
                GridOrListEntry(
                    primary_text=self._remove_extension(rom_file_name)  +" (" + self._extract_game_system(rom_info.rom_file_path)+")",
                    image_path=img_path,
                    image_path_selected=img_path,
                    description=collection,
                    icon=None,
                    value=rom_info)
            )
        return rom_list

    def get_view_type(self):
        return Theme.get_game_selection_view_type()

    def full_screen_grid_resize_type(self):
        return Theme.get_full_screen_grid_game_menu_resize_type()

    def get_set_top_bar_text_to_game_selection(self):
        return Theme.get_set_top_bar_text_to_game_selection()

    def get_game_select_row_count(self):
        return Theme.get_game_select_row_count()

    def get_game_select_col_count(self):
        return Theme.get_game_select_col_count()

    def get_game_select_carousel_col_count(self):
        return Theme.get_game_select_carousel_col_count()

    def get_image_resize_height_multiplier(self):
        return None

    def create_view(self, page_name, rom_list, selected):
        view_type = self.get_view_type()
        if view_type == ViewType.CAROUSEL:
            view_type = ViewType.FULLSCREEN_GRID

        return ViewCreator.create_view(
                        view_type=view_type,
                        top_bar_text=page_name,
                        options=rom_list,
                        selected_index=selected.get_index(),
                        rows=self.get_game_select_row_count(),
                        cols=self.get_game_select_col_count(),
                        carousel_cols=Theme.get_game_select_carousel_col_count(),
                        grid_resized_width=Theme.get_grid_game_select_img_width(),
                        grid_resized_height=Theme.get_grid_game_select_img_height(),
                        use_mutli_row_grid_select_as_backup_for_single_row_grid_select=Theme.get_game_select_show_sel_bg_grid_mode(),
                        hide_grid_bg=not Theme.get_game_select_show_sel_bg_grid_mode(),
                        show_grid_text=Theme.get_game_select_show_text_grid_mode(),
                        set_top_bar_text_to_selection=self.get_set_top_bar_text_to_game_selection(),
                        set_bottom_bar_text_to_selection=not Theme.get_set_top_bar_text_to_game_selection() and (Theme.get_game_selection_view_type() == ViewType.CAROUSEL or Theme.get_game_selection_view_type() == ViewType.GRID),
                        grid_selected_bg=Theme.get_grid_game_selected_bg(),
                        grid_resize_type=Theme.get_grid_game_selected_resize_type(),
                        grid_img_y_offset=Theme.get_grid_game_img_y_offset(),
                        carousel_selected_entry_width_percent=Theme.get_carousel_game_select_primary_img_width(),
                        carousel_shrink_further_away=Theme.get_carousel_game_select_shrink_further_away(),
                        carousel_sides_hang_off_edge=Theme.get_carousel_game_select_sides_hang_off(),
                        missing_image_path=Theme.get_missing_image_path(),
                        allow_scrolling_text=True, # roms select is allowed to scroll
                        full_screen_grid_resize_type=self.full_screen_grid_resize_type(),
                        image_resize_height_multiplier=self.get_image_resize_height_multiplier(),
                        icon_and_desc_use_image_in_place_of_icon=True)

    def _run_rom_selection(self, page_name):
        rom_list = self._get_rom_list()

        current_device = Device.get_device().get_device_name()

        filtered_roms = []
        for rom_info_ui_entry in rom_list:
            if(rom_info_ui_entry.value.game_system.game_system_config):
                devices = rom_info_ui_entry.value.game_system.game_system_config.get_devices()
                supported_device = not devices or current_device in devices
                if supported_device:
                    filtered_roms.append(rom_info_ui_entry)
            else:
                # Collections are fake without a system
                filtered_roms.append(rom_info_ui_entry)

        rom_list = filtered_roms

        return self._run_rom_selection_for_rom_list(page_name,rom_list)

    def get_additional_menu_options(self):
        return []

    def _menu_pressed(self, selection, rom_list):
        self.popup_menu.run_game_select_popup_menu(selection, self.get_additional_menu_options(), rom_list)

    def _get_menu_button_game_options(self, selection, rom_list):
        return self.popup_menu.get_game_options(selection, self.get_additional_menu_options(), rom_list, use_full_text=True)

    def _check_for_last_subfolder_existance(self, last_subfolder, rom_list):
        if (
            last_subfolder != '' and
            getattr(self, 'subfolder', '') != last_subfolder and
            getattr(self, 'subfolder', '') != '' and
            os.path.isdir(last_subfolder)
        ):
            PyUiLogger.get_logger().info(f"Subfolder does not match {last_subfolder} vs {getattr(self, 'subfolder', '') }")
            rom_info_subfolder = RomInfo(game_system=rom_list[0].get_value().game_system,rom_file_path=last_subfolder)
            return_value = self._run_subfolder_menu(rom_info_subfolder)
            if(return_value is not None and return_value != ControllerInput.B):
                return return_value

    def default_to_last_game_selection(self):
        return True

    def _get_select_view_toggle_input(self):
        combo_inputs = {ControllerInput.DPAD_LEFT, ControllerInput.DPAD_RIGHT}
        timeout_seconds = 0.5
        start_time = time.time()

        while Controller.is_held_down(ControllerInput.SELECT) and time.time() - start_time < timeout_seconds:
            queued_input = Controller.get_queued_input(timeout=0.05)
            if queued_input in combo_inputs:
                return queued_input

        return None

    def _save_current_game_selection(self, page_name, selected):
        if(
            selected is not None and
            selected.get_selection() is not None and
            selected.get_selection().get_value() is not None
        ):
            PyUiState.set_last_game_selection(
                page_name,
                selected.get_selection().get_value().rom_file_path,
                getattr(self, 'subfolder', '') or ''
            )

    def _run_rom_selection_for_rom_list(self, page_name, rom_list) :
        selected = Selection(None,None,0)
        view = None
        last_game_file_path, last_subfolder = PyUiState.get_last_game_selection(page_name)

        last_subfolder = self._check_for_last_subfolder_existance(last_subfolder, rom_list)

        if(last_subfolder is not None):
            return last_subfolder

        if(self.default_to_last_game_selection()):
            for index, entry in enumerate(rom_list):
                if(entry.get_value().rom_file_path == last_game_file_path):
                    selected = Selection(None,None,index)

        while(selected is not None):
            Display.set_page_bg(page_name)
            view_rom_list = self._get_view_rom_list(rom_list)
            view_selected = self._get_view_selection(selected, rom_list, view_rom_list)
            if(view is None):
                view = self.create_view(page_name, view_rom_list, view_selected)
            else:
                view.set_options(view_rom_list)
                if hasattr(view, "selected"):
                    view.selected = view_selected.get_index()

            accepted_inputs = [ControllerInput.A, ControllerInput.X, ControllerInput.MENU, ControllerInput.SELECT]
            selected = view.get_selection(accepted_inputs)
            if(selected is not None and (selected.get_selection() is not None or ControllerInput.B == selected.get_input())):
                if(ControllerInput.A == selected.get_input()):
                    PyUiState.set_last_game_selection(
                        page_name,
                        selected.get_selection().get_value().rom_file_path,
                        getattr(self, 'subfolder', '') or ''
                    )

                    if(selected.get_selection().get_value().is_collection):
                        PyUiState.set_last_game_selection(
                            page_name,
                            "Collection",
                            selected.get_selection().get_value().rom_file_path
                        )

                        self._load_collection_menu(selected.get_selection().get_value())

                        PyUiState.set_last_game_selection(
                            page_name,
                            selected.get_selection().get_value().rom_file_path,
                            getattr(self, 'subfolder', '') or ''
                        )

                    elif(self.launched_via_special_case(selected.get_selection().get_value())):
                        pass

                    elif(os.path.isdir(selected.get_selection().get_value().rom_file_path)):
                        # If the selected item is a directory, open it
                        PyUiState.set_last_game_selection(
                            page_name,
                            "",
                            selected.get_selection().get_value().rom_file_path
                        )
                        return_value = self._run_subfolder_menu(selected.get_selection().get_value())
                        if(return_value is not None and return_value != ControllerInput.B):
                            return return_value
                        else:
                            PyUiState.set_last_game_selection(
                            page_name,
                            selected.get_selection().get_value().rom_file_path,
                            getattr(self, 'subfolder', '') or ''
                        )

                    else:
                        RecentsManager.add_game(selected.get_selection().get_value())
                        self.run_game(selected.get_selection().get_value())
                elif(ControllerInput.X == selected.get_input() and not self.support_only_game_launching):
                    gen_additional_game_options = lambda selected=selected.get_selection().get_value(), rom_list=rom_list, self=self: self._get_menu_button_game_options(selected, rom_list)
                    GameConfigMenu(
                        selected.get_selection().get_value().game_system,
                        selected.get_selection().get_value(),
                        gen_additional_game_options
                    ).show_config(os.path.basename(selected.get_selection().get_value().rom_file_path))
                    # Regenerate as game config menu might've changed something
                    rom_list = self._get_rom_list()
                elif(ControllerInput.MENU == selected.get_input() and not self.support_only_game_launching):
                    prev_view = Theme.get_game_selection_view_type()
                    self._menu_pressed(selected.get_selection().get_value(), rom_list)
                    # Regenerate as game config menu might've changed something
                    original_length = len(rom_list)
                    rom_list = self._get_rom_list()
                    new_length = len(rom_list)
                    if(Theme.get_game_selection_view_type() != prev_view or original_length != new_length):
                        view_rom_list = self._get_view_rom_list(rom_list)
                        view_selected = self._get_view_selection(selected, rom_list, view_rom_list)
                        view = self.create_view(page_name, view_rom_list, view_selected)
                elif(ControllerInput.B == selected.get_input() and (not self.support_only_game_launching)):

                    #What is happening on muOS where this is becoming None?
                    if(selected is not None and selected.get_selection() is not None and selected.get_selection().get_value() is not None):
                        PyUiState.set_last_game_selection(
                            page_name,
                            selected.get_selection().get_value().rom_file_path,
                            getattr(self, 'subfolder', '') or ''
                        )

                        if(selected.get_selection().get_value().is_collection):
                            PyUiState.set_last_game_selection(
                                page_name,
                                "Collection",
                                selected.get_selection().get_value().rom_file_path
                            )

                    return ControllerInput.B
                elif(ControllerInput.SELECT == selected.get_input() and not self.support_only_game_launching):
                    toggle_input = self._get_select_view_toggle_input()
                    if toggle_input is not None:
                        self.popup_menu.toggle_view(reverse=toggle_input == ControllerInput.DPAD_LEFT)
                        view_rom_list = self._get_view_rom_list(rom_list)
                        view_selected = self._get_view_selection(selected, rom_list, view_rom_list)
                        view = self.create_view(page_name, view_rom_list, view_selected)
                        Controller.clear_input_queue()
                        Controller.clear_last_input()
                    elif(Theme.skip_main_menu() or Theme.merge_main_menu_and_game_menu()):
                        self._save_current_game_selection(page_name, selected)
                        return ControllerInput.SELECT

        Display.restore_bg()

    def run_game(self, game_path):
        PyUiLogger.get_logger().info("run_game(" + game_path.rom_file_path +")")
        #recents is handled one level up to account for launched_via_special_case

        game_thread: subprocess.Popen = Device.get_device().run_game(game_path)
        if (game_thread is not None):
            self.in_game_menu_listener.game_launched(
                game_thread, game_path)
            Controller.clear_input_queue()

        Display.reinitialize()
        PyUiLogger.get_logger().info("Finished run_game(" + game_path.rom_file_path +")")


    def launched_via_special_case(self, rom_info : RomInfo):
        subfolder_launch_file = rom_info.game_system.game_system_config.subfolder_launch_file()

        if(subfolder_launch_file is not None and subfolder_launch_file != ""):
            RecentsManager.add_game(rom_info)
            folder = rom_info.rom_file_path
            launch_file = os.path.join(folder,subfolder_launch_file)
            if(os.path.isfile(launch_file)):
                self.run_game(RomInfo(rom_info.game_system,launch_file))
                return True
        else:
            return False
