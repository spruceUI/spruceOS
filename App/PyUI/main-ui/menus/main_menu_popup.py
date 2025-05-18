from controller.controller_inputs import ControllerInput
from display.on_screen_keyboard import OnScreenKeyboard
from menus.games.searched_roms_menu import SearchedRomsMenu
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.view_creator import ViewCreator
from views.view_type import ViewType


class MainMenuPopup:
    def __init__(self):
        pass

    def run_popup_menu_selection(self):
        popup_options = []
        popup_options.append(GridOrListEntry(
            primary_text="Rom Search",
            image_path=Theme.settings(),
            image_path_selected=Theme.settings_selected(),
            description="",
            icon=Theme.settings(),
            value="Rom Search"
        ))

        popup_view = ViewCreator.create_view(
            view_type=ViewType.POPUP,
            options=popup_options,
            top_bar_text="Main Menu Sub Options",
            selected_index=0,
            cols=Theme.popup_menu_cols(),
            rows=Theme.popup_menu_rows)
        
        while (popup_selection := popup_view.get_selection()):
            if(popup_selection.get_input() is not None):
                break
        
        if(popup_selection.get_input() is not None):
            popup_view.view_finished()

        if(ControllerInput.A == popup_selection.get_input()): 
            if("Rom Search" == popup_selection.get_selection().get_primary_text()):
                search_txt = OnScreenKeyboard().get_input("Game Search:")
                if(search_txt is not None):
                    SearchedRomsMenu(search_txt.upper()).run_rom_selection()
