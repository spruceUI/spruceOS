

from controller.controller_inputs import ControllerInput
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.view_creator import ViewCreator
from views.view_type import ViewType

from menus.language.language import Language

CONTINUE_RUNNING = True

class InGameMenuPopup:
    def __init__(self):
        pass

    def exit_game(self, input):
        return False

    def run_in_game_menu(self):
        popup_options = []
    
        popup_options.append(GridOrListEntry(
            primary_text=Language.exit_game(),
            image_path=Theme.settings(),
            image_path_selected=Theme.settings_selected(),
            description="",
            icon=Theme.settings(),
            value=self.exit_game
        ))
        

        popup_view = ViewCreator.create_view(
            view_type=ViewType.TEXT_ONLY,
            options=popup_options,
            top_bar_text="Main Menu Sub Options",
            selected_index=0,
            cols=Theme.popup_menu_cols(),
            rows=Theme.popup_menu_rows())
        
        while (popup_selection := popup_view.get_selection()):
            if(popup_selection.get_input() is not None):
                break
        
        if(ControllerInput.A == popup_selection.get_input()): 
            return popup_selection.get_selection().get_value()(popup_selection.get_input())

        return True