
import json
import os
import sys

from display.font_purpose import FontPurpose
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig


class Language:
    _data = {}
    _config_path = None
    @classmethod

    def init(cls):
        cls._data = {}
        cls.load()

    @classmethod
    def load(cls):
        language = PyUiConfig.get_language()
        if(language is not None):
            #PyUiLogger.get_logger().info(f"language is {language}")
            base_dir = os.path.abspath(sys.path[0])
            parent_dir = os.path.dirname(base_dir)
            lang_dir = os.path.join(parent_dir, "lang")
            cls._config_path = os.path.join(lang_dir, language+".json")
        else:
            cls._config_path = None
        cls._read_from_file(cls._config_path)

    @classmethod
    def _read_from_file(cls, filepath):
        if(filepath is not None):
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    cls._data = json.load(f)
                    #PyUiLogger.get_logger().info(f"Languages loaded from {filepath}")
            except FileNotFoundError:
                PyUiLogger.get_logger().error(f"Languages file not found: {filepath}, using defaults.")
                cls._data = {}
            except json.JSONDecodeError:
                PyUiLogger.get_logger().error(f"Invalid JSON in languages file: {filepath}, using defaults.")
                cls._data = {}
        else:
            PyUiLogger.get_logger().error(f"Languages file not found: {filepath}, using defaults.")
            cls._data = {}

    @classmethod
    def save(cls):
        cls._write_to_file(cls._config_path)
        cls.load()

    @classmethod
    def _write_to_file(cls, filepath):
        try:
            os.makedirs(os.path.dirname(filepath), exist_ok=True)
            with open(filepath, 'w', encoding='utf-8') as f:
                json.dump(cls._data, f, indent=4)
            PyUiLogger.get_logger().info(f"Settings saved to {filepath}")
        except Exception as e:
            PyUiLogger.get_logger().error(f"Failed to write settings to {filepath}: {e}")

    @classmethod
    def __contains__(cls, key):
        return key in cls._data

    @classmethod
    def get(cls, key, default=None):
        return cls._data.get(key, default)

    @classmethod
    def set(cls, key, value):
        cls._data[key] = value

    @classmethod
    def __getitem__(cls, key):
        return cls._data.get(key)

    @classmethod
    def __setitem__(cls, key, value):
        cls._data[key] = value

    @classmethod
    def to_dict(cls):
        return cls._data.copy()

    @classmethod
    def clear(cls):
        cls._data.clear()

    @classmethod
    def get_fonts_dir(cls):
        base_dir = os.path.abspath(sys.path[0])
        parent_dir = os.path.dirname(base_dir)
        return os.path.join(parent_dir, "fonts")

    @classmethod
    def get_display_name_for_file(cls, language_file: str) -> str:
        base_dir = os.path.abspath(sys.path[0])
        parent_dir = os.path.dirname(base_dir)
        lang_path = os.path.join(parent_dir, "lang", f"{language_file}.json")
        try:
            with open(lang_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            return data.get("displayName", language_file)
        except Exception:
            return language_file

    @classmethod
    def display_name(cls) -> str:
        return cls._data.get("displayName", PyUiConfig.get_language() or "English")

    @classmethod
    def label(cls, key: str, default: str) -> str:
        return cls._data.get(key, default)

    @classmethod
    def enum_label(cls, section: str, name: str, default: str | None = None) -> str:
        section_data = cls._data.get(section)
        if isinstance(section_data, dict) and name in section_data:
            return section_data[name]
        if default is not None:
            return default
        return name.replace("_", " ").title()

    @classmethod
    def boolean_label(cls, value) -> str:
        if isinstance(value, bool):
            key = "true" if value else "false"
        else:
            key = str(value).lower()
        booleans = cls._data.get("booleans", {})
        if key in booleans:
            return booleans[key]
        return str(value)

    @classmethod
    def on_off_label(cls, enabled: bool) -> str:
        on_off = cls._data.get("onOff", {})
        key = "on" if enabled else "off"
        return on_off.get(key, "On" if enabled else "Off")

    @classmethod
    def view_type_label(cls, view_type) -> str:
        return cls.enum_label("viewTypes", view_type.name, view_type.name.replace("_", " ").title())

    @classmethod
    def resize_type_label(cls, resize_type) -> str:
        return cls.enum_label("resizeTypes", resize_type.name, resize_type.name)

    @classmethod
    def controller_input_label(cls, controller_input) -> str:
        return cls.enum_label("controllerInputs", controller_input.name, controller_input.name)

    @classmethod
    def game_system_sort_mode_label(cls, mode: str) -> str:
        return cls.enum_label("gameSystemSortModes", mode, mode)

    @classmethod
    def game_system_label(cls, system_key: str, default: str) -> str:
        systems = cls._data.get("gameSystems", {})
        if system_key in systems:
            return systems[system_key]
        return default

    @classmethod
    def menu_option_display(cls, display: str) -> str:
        displays = cls._data.get("menuOptionDisplays", {})
        return displays.get(display, display)

    @classmethod
    def menu_option_description(cls, description: str) -> str:
        if not description:
            return description
        descriptions = cls._data.get("menuOptionDescriptions", {})
        return descriptions.get(description, description)

    @classmethod
    def settings_category(cls, category: str) -> str:
        categories = cls._data.get("settingsCategories", {})
        return categories.get(category, category)

    @classmethod
    def menu_option_value(cls, value) -> str:
        if value is None:
            return ""
        if isinstance(value, bool):
            return cls.boolean_label(value)
        text = str(value)
        if text in ("True", "False"):
            return cls.boolean_label(text == "True")
        values = cls._data.get("menuOptionValues", {})
        if text in values:
            return values[text]
        governor = cls._data.get("governorOptions", {})
        if text in governor:
            return governor[text]
        return text

    @classmethod
    def select_option_prompt(cls, name: str) -> str:
        template = cls.label("selectOptionPrompt", "Select a {name}")
        return template.replace("{name}", name)

    @classmethod
    def governor_option_label(cls, value: str) -> str:
        options = cls._data.get("governorOptions", {})
        return options.get(value, value)

    @classmethod
    def launch_option_name(cls, name: str) -> str:
        options = cls._data.get("launchOptions", {})
        return options.get(name, name)

    @classmethod
    def screen_type_label(cls, screen_type: str) -> str:
        return cls.enum_label("screenTypes", screen_type, screen_type)

    @classmethod
    def _font_config_key_for_purpose(cls, font_purpose: FontPurpose) -> str:
        match font_purpose:
            case FontPurpose.GRID_ONE_ROW | FontPurpose.GRID_MULTI_ROW | FontPurpose.LIST_INDEX | FontPurpose.LIST_TOTAL:
                return "grid"
            case FontPurpose.SHADOWED | FontPurpose.SHADOWED_BACKDROP | FontPurpose.SHADOWED_SMALL | FontPurpose.SHADOWED_BACKDROP_SMALL:
                return "shadowed"
            case _:
                return "list"

    @classmethod
    def font_purpose_size_label(cls, font_purpose: FontPurpose) -> str:
        purposes = cls._data.get("fontPurposeSizes", {})
        if font_purpose.name in purposes:
            return purposes[font_purpose.name]
        size_suffix = cls._data.get("size", "Size")
        return f"{font_purpose.name} {size_suffix}"

    @classmethod
    def get_font_for_purpose(cls, font_purpose: FontPurpose):
        fonts_config = cls._data.get("fonts")
        if not fonts_config:
            return None

        filename = fonts_config.get(cls._font_config_key_for_purpose(font_purpose))
        if not filename:
            filename = fonts_config.get("default")

        if not filename:
            return None

        font_path = os.path.join(cls.get_fonts_dir(), filename)
        if os.path.exists(font_path):
            return font_path

        PyUiLogger.get_logger().warning(f"Language font not found: {font_path}")
        return None

    @classmethod
    def games(cls):
        return cls._data.get("Games","Games")

    @classmethod
    def recents(cls):
        return cls._data.get("Recents","Recents")

    @classmethod
    def apps(cls):
        return cls._data.get("Apps","Apps")

    @classmethod
    def collections(cls):
        return cls._data.get("Collections","Collections")

    @classmethod
    def favorites(cls):
        return cls._data.get("Favorites","Favorites")

    @classmethod
    def settings(cls):
        return cls._data.get("Settings","Settings")

    @classmethod
    def no_entries_found(cls):
        return cls._data.get("noEntriesFound","No Entries Found")

    @classmethod
    def system_game_search(cls):
        return cls._data.get("systemGameSearch","$system Game Search")

    @classmethod
    def all_system_game_search(cls):
        return cls._data.get("allSystemGameSearch","All System Game Search")

    @classmethod
    def system_menu_sub_options(cls):
        return cls._data.get("systemMenuSubOptions","$system Menu Sub Options")

    @classmethod
    def game_search(cls):
        return cls._data.get("gameSearch","Game Search:")

    @classmethod
    def exit_py_ui(cls):
        return cls._data.get("exitPyUi","Exit")

    
    
    

    # ---- Auto-generated language entries ----

    @classmethod
    def set_pyui_as_startup(cls):
        return cls._data.get("setPyuiAsStartup","Set PyUI as Startup")

    @classmethod
    def rom_search(cls):
        return cls._data.get("romSearch","Rom Search")

    @classmethod
    def settings_1(cls):
        return cls._data.get("Settings","Settings")

    @classmethod
    def recents_1(cls):
        return cls._data.get("Recents","Recents")

    @classmethod
    def favorites_1(cls):
        return cls._data.get("Favorites","Favorites")

    @classmethod
    def collections_1(cls):
        return cls._data.get("Collections","Collections")

    @classmethod
    def show_app(cls):
        return cls._data.get("showApp","Show App")

    @classmethod
    def hide_hidden_apps(cls):
        return cls._data.get("hideHiddenApps","Hide Hidden Apps")

    @classmethod
    def sort_favorites(cls):
        return cls._data.get("sortFavorites","Sort Favorites")

    @classmethod
    def toggle_settings_as_game_specific_override(cls):
        return cls._data.get("toggleSettingsAsGameSpecificOverride","Toggle Settings as Game Specific Override")

    @classmethod
    def remove_favorite(cls):
        return cls._data.get("removeFavorite","Remove Favorite")

    @classmethod
    def add_favorite(cls):
        return cls._data.get("addFavorite","Add Favorite")

    @classmethod
    def remove_gameswitcher_game(cls):
        return cls._data.get("removeGameSwitcherGame","Remove from GameSwitcher")
    
    @classmethod
    def add_gameswitcher_game(cls):
        return cls._data.get("addGameSwitcherGame","Add to GameSwitcher")

    @classmethod
    def add_remove_collection(cls):
        return cls._data.get("addRemoveCollection","Add/Remove Collection")
    
    @classmethod
    def remove_recents(cls):
        return cls._data.get("removeRecents","Remove Recents")

    @classmethod
    def launch_random_game(cls):
        return cls._data.get("launchRandomGame","Launch Random Game")

    @classmethod
    def exit_game(cls):
        return cls._data.get("exitGame","Exit Game")

    @classmethod
    def save_state(cls):
        return cls._data.get("saveState","Save State")

    @classmethod
    def load_state(cls):
        return cls._data.get("loadState","Load State")

    @classmethod
    def toggle_fast_forward(cls):
        return cls._data.get("toggleFastForward","Toggle Fast Forward")

    @classmethod
    def ra_menu(cls):
        return cls._data.get("raMenu","RA Menu")

    @classmethod
    def create_new_collection(cls):
        return cls._data.get("createNewCollection","Create New Collection")

    @classmethod
    def add_to(cls):
        return cls._data.get("addTo","Add to")

    @classmethod
    def add_to_collection(cls):
        return cls._data.get("addToCollection","Add to Collection")

    @classmethod
    def remove_from(cls):
        return cls._data.get("removeFrom","Remove from")

    @classmethod
    def power_off(cls):
        return cls._data.get("powerOff","Power Off")

    @classmethod
    def backlight(cls):
        return cls._data.get("Backlight","Backlight")

    @classmethod
    def volume(cls):
        return cls._data.get("Volume","Volume")

    @classmethod
    def wifi(cls):
        return cls._data.get("WiFi","WiFi")

    @classmethod
    def bluetooth(cls):
        return cls._data.get("Bluetooth","Bluetooth")

    @classmethod
    def theme(cls):
        return cls._data.get("Theme","Theme")

    @classmethod
    def theme_settings(cls):
        return cls._data.get("themeSettings","Theme Settings")

    @classmethod
    def sound_settings(cls):
        return cls._data.get("soundSettings","Sound Settings")

    @classmethod
    def additional_settings(cls):
        return cls._data.get("additionalSettings","Additional Settings")


    @classmethod
    def tasks(cls):
        return cls._data.get("tasks","Tasks")

    @classmethod
    def status(cls):
        return cls._data.get("Status","Status")

    @classmethod
    def calibrate_analog_sticks(cls):
        return cls._data.get("calibrateAnalogSticks","Calibrate Analog Sticks")

    @classmethod
    def remap_buttons(cls):
        return cls._data.get("remapButtons","Remap Buttons")

    @classmethod
    def brightness(cls):
        return cls._data.get("Brightness","Brightness")

    @classmethod
    def contrast(cls):
        return cls._data.get("Contrast","Contrast")

    @classmethod
    def saturation(cls):
        return cls._data.get("Saturation","Saturation")

    @classmethod
    def hue(cls):
        return cls._data.get("Hue","Hue")

    @classmethod
    def red(cls):
        return cls._data.get("Red","Red")

    @classmethod
    def blue(cls):
        return cls._data.get("Blue","Blue")

    @classmethod
    def green(cls):
        return cls._data.get("Green","Green")

    @classmethod
    def display_settings(cls):
        return cls._data.get("displaySettings","Display Settings")

    @classmethod
    def time_settings(cls):
        return cls._data.get("timeSettings","Time Settings")

    @classmethod
    def game_system_select_settings(cls):
        return cls._data.get("gameSystemSelectSettings","Game System Select Settings")

    @classmethod
    def game_select_settings(cls):
        return cls._data.get("gameSelectSettings","Game Select Settings")

    @classmethod
    def game_switcher_settings(cls):
        return cls._data.get("gameSwitcherSettings","Game Switcher Settings")

    @classmethod
    def game_art_display_settings(cls):
        return cls._data.get("gameArtDisplaySettings","Game Art Display Settings")

    @classmethod
    def download_boxart(cls):
        return cls._data.get("downloadBoxart","Download BoxArt")

    @classmethod
    def select_boxart(cls):
        return cls._data.get("selectBoxart","Select BoxArt Download")

    @classmethod
    def delete_boxart(cls):
        return cls._data.get("deleteBoxart","Delete Box Art")

    @classmethod
    def delete_rom(cls):
        return cls._data.get("deleteRom","Delete ROM")

    @classmethod
    def controller_settings(cls):
        return cls._data.get("controllerSettings","Controller Settings")

    @classmethod
    def language_settings(cls):
        return cls._data.get("languageSettings","Language Settings")

    @classmethod
    def animation_settings(cls):
        return cls._data.get("animationSettings","Animation Settings")

    @classmethod
    def animations_enabled(cls):
        return cls._data.get("animationsEnabled","Animations Enabled")

    @classmethod
    def animation_speed(cls):
        return cls._data.get("animationSpeed","Animation Speed")

    @classmethod
    def input_rate_limit_ms(cls):
        return cls._data.get("inputRateLimitMs","Input Rate Limiting (ms)")

    @classmethod
    def stock_os_menu(cls):
        return cls._data.get("stockOsMenu","Stock OS Menu")

    @classmethod
    def optimize_boxart(cls):
        return cls._data.get("optimizeBoxart","Optimize Boxart")

    @classmethod
    def locked_down_modes(cls):
        return cls._data.get("lockedDownModes","Enable Locked Down Modes")

    @classmethod
    def l2_r2_skip_by_letter_for_daijisho_themes(cls):
        return cls._data.get("l2R2SkipByLetterForDaijishoThemes","L2/R2 Skip By Letter for Daijisho Themes")

    @classmethod
    def ignore_articles_when_sorting(cls):
        return cls._data.get("ignoreArticlesWhenSorting","Ignore articles when sorting")

    @classmethod
    def hold_menu_for_gameswitcher(cls):
        return cls._data.get("holdMenuForGameswitcher","Hold Menu for GameSwitcher")

    @classmethod
    def prefer_savestate_screenshots(cls):
        return cls._data.get("preferSavestateScreenshots","Prefer SaveState Screenshots")

    @classmethod
    def game_count(cls):
        return cls._data.get("gameCount","Game Count")

    @classmethod
    def view_type(cls):
        return cls._data.get("viewType","View Type")

    @classmethod
    def full_screen_resize_type(cls):
        return cls._data.get("fullScreenResizeType","Full Screen Resize Type")

    @classmethod
    def true_full_screen(cls):
        return cls._data.get("trueFullScreen","True Full Screen")

    @classmethod
    def topbar_gamename(cls):
        return cls._data.get("topbarGamename","TopBar = GameName")

    @classmethod
    def use_recents_for_gameswitcher(cls):
        return cls._data.get("useRecentsForGameswitcher","Use Recents for GameSwitcher")

    @classmethod
    def show_all_systems(cls):
        return cls._data.get("showAllSystems","Show All Systems")

    @classmethod
    def game_system_sorting(cls):
        return cls._data.get("gameSystemSorting","Game System Sorting")

    @classmethod
    def system_type_priority(cls):
        return cls._data.get("systemTypePriority","System Type Priority")

    @classmethod
    def system_brand_priority(cls):
        return cls._data.get("systemBrandPriority","System Brand Priority")

    @classmethod
    def system_year_priority(cls):
        return cls._data.get("systemYearPriority","System Year Priority")

    @classmethod
    def system_name_priority(cls):
        return cls._data.get("systemNamePriority","System Name Priority")

    @classmethod
    def enter_game_selection_only_mode(cls):
        return cls._data.get("enterGameSelectionOnlyMode","Enter Game Selection Only Mode")

    @classmethod
    def enter_simple_mode(cls):
        return cls._data.get("enterSimpleMode","Enter Simple Mode")

    @classmethod
    def year(cls):
        return cls._data.get("Year","Year")

    @classmethod
    def month(cls):
        return cls._data.get("Month","Month")

    @classmethod
    def day(cls):
        return cls._data.get("Day","Day")

    @classmethod
    def hour24(cls):
        return cls._data.get("hour24","Hour 24")

    @classmethod
    def minute(cls):
        return cls._data.get("Minute","Minute")

    @classmethod
    def play_button_press_sound(cls):
        return cls._data.get("playButtonPressSound","Play Button Press Sound")

    @classmethod
    def play_bgm(cls):
        return cls._data.get("playBgm","Play BGM")

    @classmethod
    def bgm_volume(cls):
        return cls._data.get("bgmVolume","BGM Volume")

    @classmethod
    def set_time_date(cls):
        return cls._data.get("setTimeDate","Set Time & Date")

    @classmethod
    def set_timezone(cls):
        return cls._data.get("setTimezone","Set Timezone")

    @classmethod
    def clock(cls):
        return cls._data.get("Clock","Clock")

    @classmethod
    def twenty_four_hour_clock(cls):
        return cls._data.get("24HourClock","24 Hour Clock")

    @classmethod
    def show_am_pm(cls):
        return cls._data.get("showAmPm","Show AM/PM")

    @classmethod
    def game_sel_menu(cls):
        return cls._data.get("gameSelMenu","Game Sel Menu")

    @classmethod
    def img_mode(cls):
        return cls._data.get("imgMode","Img Mode")

    @classmethod
    def rows(cls):
        return cls._data.get("Rows","Rows")

    @classmethod
    def cols(cls):
        return cls._data.get("Cols","Cols")

    @classmethod
    def img_width(cls):
        return cls._data.get("imgWidth","Img Width")

    @classmethod
    def img_height(cls):
        return cls._data.get("imgHeight","Img Height")

    @classmethod
    def prim_img_width(cls):
        return cls._data.get("primImgWidth","Prim Img Width %")

    @classmethod
    def prim_img_height(cls):
        return cls._data.get("primImgHeight","Prim Img Height %")

    @classmethod
    def shrink_further_away(cls):
        return cls._data.get("shrinkFurtherAway","Shrink Further Away")

    @classmethod
    def boxart_resize_type(cls):
        return cls._data.get("boxartResizeType","BoxArt Resize Type")

    @classmethod
    def sel_bg_resize_pad_width(cls):
        return cls._data.get("selBgResizePadWidth","Sel BG Resize Pad Width")

    @classmethod
    def sel_bg_resize_pad_height(cls):
        return cls._data.get("selBgResizePadHeight","Sel BG Resize Pad Height")

    @classmethod
    def set_single_row_grid_text_y_offset(cls):
        return cls._data.get("setSingleRowGridTextYOffset","1 Row Grid Text Y Offset")

    @classmethod
    def set_multi_row_grid_text_y_offset(cls):
        return cls._data.get("setMultiRowGridTextYOffset",">1 Row Grid Text Y Offset")

    @classmethod
    def set_grid_multi_row_img_y_offset(cls):
        return cls._data.get("setGridMultiRowImageYOffset",">1 Row Grid Image Y Offset")

    @classmethod
    def skip_main_menu(cls):
        return cls._data.get("skipMainMenu","Skip Main Menu")

    @classmethod
    def merge_main_menu_and_game_menu(cls):
        return cls._data.get("mergeMainMenuAndGameMenu","Merge Main Menu And Game Menu")

    @classmethod
    def show_extras_in_system_select_menu(cls):
        return cls._data.get("showExtrasInSystemSelectMenu","Show Apps/Recents/Favs/Collections")

    @classmethod
    def main_menu(cls):
        return cls._data.get("mainMenu","Main Menu")

    @classmethod
    def main_menu_columns(cls):
        return cls._data.get("mainMenuColumns","Main Menu Columns")

    @classmethod
    def main_menu_rows(cls):
        return cls._data.get("mainMenuRows","Main Menu Rows")

    @classmethod
    def show_text(cls):
        return cls._data.get("showText","Show Text")

    @classmethod
    def show_recents(cls):
        return cls._data.get("showRecents","Show Recents")

    @classmethod
    def show_collections(cls):
        return cls._data.get("showCollections","Show Collections")

    @classmethod
    def show_favorites(cls):
        return cls._data.get("showFavorites","Show Favorites")

    @classmethod
    def show_apps(cls):
        return cls._data.get("showApps","Show Apps")

    @classmethod
    def show_settings(cls):
        return cls._data.get("showSettings","Show Settings")

    @classmethod
    def main_menu_theme_options(cls):
        return cls._data.get("mainMenuThemeOptions","Main Menu Theme Options")

    @classmethod
    def system_select_theme_options(cls):
        return cls._data.get("systemSelectThemeOptions","System Select Theme Options")

    @classmethod
    def game_select_menu_theme_options(cls):
        return cls._data.get("gameSelectMenuThemeOptions","Game Select Menu Theme Options")

    @classmethod
    def fonts(cls):
        return cls._data.get("Fonts","Fonts")

    @classmethod
    def grid_view_theme_options(cls):
        return cls._data.get("gridViewThemeOptions","Grid View Theme Options")

    @classmethod
    def top_and_bottom_bar_options(cls):
        return cls._data.get("topAndBottomBarOptions","Top and Bottom Bar Options")

    @classmethod
    def left_side_initial_x_offset(cls):
        return cls._data.get("leftSideInitialXOffset","Left Side Initial X Offset")

    @classmethod
    def aboutThisDevice(cls):
        return cls._data.get("aboutThisDevice","About this Device")

