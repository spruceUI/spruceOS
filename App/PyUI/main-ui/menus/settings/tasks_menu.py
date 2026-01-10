
from controller.controller_inputs import ControllerInput
from devices.device import Device
from games.utils.box_art_resizer import BoxArtResizer
from menus.language.language import Language
from menus.settings import settings_menu
from menus.settings.modes_menu import ModesMenu
from option_select_ui import OptionSelectUI
from utils.boxart.box_art_scraper import BoxArtScraper
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.view_type import ViewType


class TasksMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()

    def resize_boxart(self, input):
        if (ControllerInput.A == input):
            BoxArtResizer.patch_boxart()
            
    def scrape_box_art(self,input):
        if(ControllerInput.A == input):
            BoxArtScraper().scrape_boxart()

    def launch_modes_menu(self,input):
        if(ControllerInput.A == input):
            ModesMenu().show_menu()



    def build_options_list(self):
        option_list = []

        option_list.append(
                GridOrListEntry(
                        primary_text=Language.download_boxart(),
                        image_path=None,
                        image_path_selected=None,
                        description="Scan entire library for missing boxart",
                        icon=None,
                        value=self.scrape_box_art
                )
         )    

        if(Device.get_device().supports_image_resizing()):
            option_list.append(
                GridOrListEntry(
                    primary_text=Language.optimize_boxart(),
                    value_text=None,
                    image_path=None,
                    image_path_selected=None,
                    description="Resize boxart and convert to QOI for faster loading",
                    icon=None,
                    value=self.resize_boxart
                )
            )  
                    
        option_list.append(
            GridOrListEntry(
                primary_text=Language.locked_down_modes(),
                value_text=None,
                image_path=None,
                image_path_selected=None,
                description="Simpler modes for new users or kids",
                icon=None,
                value=self.launch_modes_menu
                )
            )

        if(PyUiConfig.cfw_tasks_json() is not None):
            option_list.extend(self.get_cfw_tasks())

            

        return option_list

    def get_cfw_tasks(self):
        return OptionSelectUI.get_top_level_options_from_json(PyUiConfig.cfw_tasks_json(),ViewType.ICON_AND_DESC, execute_immediately=True)