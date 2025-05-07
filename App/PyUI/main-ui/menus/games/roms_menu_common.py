
import os
from pathlib import Path
from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from devices.device import Device
from display.display import Display
from display.render_mode import RenderMode
from menus.games.game_config_menu import GameConfigMenu
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.image_list_view import ImageListView
from views.selection import Selection
from abc import ABC, abstractmethod

from views.view_creator import ViewCreator
from views.view_type import ViewType


class RomsMenuCommon(ABC):
    def __init__(self, display: Display, controller: Controller, device: Device, theme: Theme):
        self.display : Display= display
        self.controller : Controller = controller
        self.device : Device= device
        self.theme : Theme= theme
        self.view_creator = ViewCreator(display,controller,device,theme)

    def _remove_extension(self,file_name):
        return os.path.splitext(file_name)[0]
    
    def _get_image_path(self, rom_path):
        # Get the base filename without extension (e.g., "DKC")
        base_name = os.path.splitext(os.path.basename(rom_path))[0]
        
        # Get the parent directory of the ROM file
        parent_dir = os.path.dirname(rom_path)
        
        # Construct the path to the Imgs directory
        imgs_dir = os.path.join(parent_dir, "Imgs")
        
        # Construct the full path to the PNG image
        image_path = os.path.join(imgs_dir, base_name + ".png")
        if os.path.exists(image_path):
            return image_path
        else:
            return None
        
    def _extract_game_system(self, rom_path):
        rom_path = os.path.abspath(os.path.normpath(rom_path))
        parts = os.path.normpath(rom_path).split(os.sep)
        try:
            roms_index = parts.index("Roms")
            return parts[roms_index + 1]
        except (ValueError, IndexError) as e:
            print(f"Error extracting subdirectory after 'Roms' for {rom_path}: {e}")
        return None  # "Roms" not found or no subdirectory after it
    
    @abstractmethod
    def _get_rom_list(self) -> list[GridOrListEntry]:
        pass

    def _run_rom_selection(self, page_name) :
        selected = Selection(None,None,0)
        # Regenerate as part of while loop in case the options menu changes anything
        while(selected is not None):
            rom_list = self._get_rom_list()

            view = self.view_creator.create_view(
                view_type=ViewType.TEXT_AND_IMAGE_LIST_VIEW,
                top_bar_text=page_name,
                options=rom_list,
                selected_index=selected.get_index())
            selected = view.get_selection([ControllerInput.A, ControllerInput.X])
            if(selected is not None):
                if(ControllerInput.A == selected.get_input()):
                    self.display.deinit_display()
                    self.device.run_game(selected.get_selection().get_value())
                    self.controller.clear_input_queue()
                    self.display.reinitialize()
                elif(ControllerInput.X == selected.get_input()):
                    GameConfigMenu(self.display, self.controller, self.device, self.theme, 
                                   self._extract_game_system(selected.get_selection().get_value()), 
                                   selected.get_selection().get_value()).show_config()
