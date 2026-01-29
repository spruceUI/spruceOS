from controller.controller_inputs import ControllerInput
from display.on_screen_keyboard import OnScreenKeyboard
from menus.games.collections_menu import CollectionsMenu
from menus.games.favorites_menu import FavoritesMenu
from menus.games.recents_menu import RecentsMenu
from menus.games.searched_roms_menu import SearchedRomsMenu
from menus.settings.basic_settings_menu import BasicSettingsMenu
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.view_creator import ViewCreator
from views.view_type import ViewType


from menus.language.language import Language

class MainMenuPopup:
    def __init__(self):
        pass

    def rom_search(self, input):
        if (ControllerInput.A == input):
            search_txt = OnScreenKeyboard().get_input("Game Search:")
            if (search_txt is not None):
                return SearchedRomsMenu(search_txt.upper()).run_rom_selection()

    def open_settings(self, input):
        if (ControllerInput.A == input):
            BasicSettingsMenu().show_menu()
            
    def open_recents(self, input):
        if (ControllerInput.A == input):
            RecentsMenu().run_rom_selection()

    def open_favorites(self, input):
        if (ControllerInput.A == input):
            FavoritesMenu().run_rom_selection()

    def open_collections(self, input):
        if (ControllerInput.A == input):
            CollectionsMenu().run_rom_selection()


    def run_popup_menu_selection(self):
        popup_options = []
        popup_options.append(GridOrListEntry(
            primary_text=Language.rom_search(),
            image_path=None,
            image_path_selected=None,
            description="",
            icon=None,
            value=self.rom_search
        ))
        popup_options.append(GridOrListEntry(
            primary_text=Language.settings_1(),
            image_path=None,
            image_path_selected=None,
            description="",
            icon=None,
            value=self.open_settings
        ))

        if(not Theme.get_recents_enabled()):
            popup_options.append(
                    GridOrListEntry(
                        primary_text=Language.recents_1(),
                        image_path=None,
                        image_path_selected=None,
                        description="",
                        icon=None,
                        value=self.open_recents
                    )
                )
            
        if(not Theme.get_favorites_enabled()):            
            popup_options.append(
                    GridOrListEntry(
                        primary_text=Language.favorites_1(),
                        image_path=None,
                        image_path_selected=None,
                        description="",
                        icon=None,
                        value=self.open_favorites
                    )
                )

        if(not Theme.get_collections_enabled()):
            popup_options.append(
                    GridOrListEntry(
                        primary_text=Language.collections_1(),
                        image_path=None,
                        image_path_selected=None,
                        description="",
                        icon=None,
                        value=self.open_collections
                    )
                )


        popup_view = ViewCreator.create_view(
            view_type=ViewType.POPUP,
            options=popup_options,
            top_bar_text="Main Menu Sub Options",
            selected_index=0,
            cols=Theme.popup_menu_cols(),
            rows=Theme.popup_menu_rows)

        while (popup_selection := popup_view.get_selection()):
            if (popup_selection.get_input() is not None):
                break

        if (popup_selection.get_input() is not None):
            popup_view.view_finished()

        if(popup_selection.get_input() is not None):
            popup_selection.get_selection().get_value()(popup_selection.get_input())
