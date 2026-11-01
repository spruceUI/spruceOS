

from controller.controller_inputs import ControllerInput
from devices.device import Device
from menus.settings import settings_menu
from menus.common import symbols
from utils.user_prompt import UserPrompt
from views.grid_or_list_entry import GridOrListEntry


from menus.language.language import Language

# The Konami sequence's own glyphs: the D-pad and Start/Select of promptfont's Xbox set,
# matching symbols.BTN_A / symbols.BTN_B (codepoints follow promptfont's glyphs.json, not
# the Unicode names - see menus/common/symbols.py).
DPAD_UP = "≻"      # U+227B xbox-dpad-up
DPAD_DOWN = "≽"    # U+227D xbox-dpad-down
DPAD_LEFT = "≺"    # U+227A xbox-dpad-left
DPAD_RIGHT = "≼"   # U+227C xbox-dpad-right
BTN_START = "⇸"    # U+21F8 gamepad-start
BTN_SELECT = "⇷"   # U+21F7 gamepad-select

# The sequence as button segments, one press per run: every press separated by a single
# space - including the arrows, so the whole line reads as a sequence rather than a tight
# arrow blob followed by loose buttons.
KONAMI = symbols.glyph_runs([
    DPAD_UP, DPAD_UP, DPAD_DOWN, DPAD_DOWN,
    DPAD_LEFT, DPAD_RIGHT, DPAD_LEFT, DPAD_RIGHT,
    symbols.BTN_B, symbols.BTN_A, BTN_START, BTN_SELECT,
])

class ModesMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()

    def prompt_games_only_mode(self,input):
        if(ControllerInput.A == input):
            if UserPrompt.prompt_yes_no(Language.label("gameOnlyModeTitle", "Game Selection Only Mode"),
                                        [Language.label("gameOnlyModePrompt1", "Would you like to enter game selection only mode?"),
                                         Language.label("gameOnlyModePrompt2", "Boot straight into the game selection screen"),
                                         Language.label("gameOnlyModePrompt3", "To exit enter the Konami Code"), 
                                         KONAMI]):
                Device.get_device().get_system_config().set_game_selection_only_mode_enabled(True)
                Device.get_device().exit_pyui()
            else:
                return

    def prompt_simple_mode(self,input):
        if(ControllerInput.A == input):
            if UserPrompt.prompt_yes_no(Language.label("simpleModeTitle", "Simple Mode"),
                                        [Language.label("simpleModePrompt1", "Would you like to enter simple mode?"),
                                         Language.label("simpleModePrompt2", "It has restricted access to settings"),
                                         Language.label("simpleModePrompt3", "To exit enter the Konami Code"), 
                                         KONAMI]):
                Device.get_device().get_system_config().set_simple_mode_enabled(True)
                Device.get_device().exit_pyui()
            else:
                return

    def build_options_list(self):
        option_list = []
        

        option_list.append(
            GridOrListEntry(
                primary_text=Language.enter_game_selection_only_mode(),
                value_text=None,
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.prompt_games_only_mode
                )
            )
        option_list.append(
            GridOrListEntry(
                primary_text=Language.enter_simple_mode(),
                value_text=None,
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.prompt_simple_mode
                )
            )


        return option_list
