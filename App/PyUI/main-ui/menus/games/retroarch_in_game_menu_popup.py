

import socket
import time
from controller.controller_inputs import ControllerInput
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry
from views.view_creator import ViewCreator
from views.view_type import ViewType

from menus.language.language import Language

CONTINUE_RUNNING = True

class RetroarchInGameMenuPopup:
    def __init__(self):
        pass
        
    def send_cmd_to_ra(self, cmd):
        ra_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); 
        ra_socket.sendto(cmd, ('127.0.0.1', 55355))

    def exit_game(self, input):
        if(ControllerInput.A == input):
            self.send_cmd_to_ra(b'QUIT')
            return False
        else:
            return True
    def save_state(self, input):
        if(ControllerInput.A == input):
            self.send_cmd_to_ra(b'SAVE_STATE')
        return True
    
    def load_state(self, input):
        if(ControllerInput.A == input):
            self.send_cmd_to_ra(b'LOAD_STATE')
        return True
    
    def fast_forward(self, input):
        if(ControllerInput.A == input):
            self.send_cmd_to_ra(b'FAST_FORWARD_HOLD')
        return True
    
    def ra_menu(self, input):
        if(ControllerInput.A == input):
            self.send_cmd_to_ra(b'MENU_TOGGLE')
        return True

    def run_in_game_menu(self):
        time.sleep(0.1)
        popup_options = []
        popup_options.append(GridOrListEntry(
            primary_text=Language.save_state(),
            image_path=Theme.settings(),
            image_path_selected=Theme.settings_selected(),
            description="",
            icon=Theme.settings(),
            value=self.save_state
        ))

        popup_options.append(GridOrListEntry(
            primary_text=Language.load_state(),
            image_path=Theme.settings(),
            image_path_selected=Theme.settings_selected(),
            description="",
            icon=Theme.settings(),
            value=self.load_state
        ))

        popup_options.append(GridOrListEntry(
            primary_text=Language.toggle_fast_forward(),
            image_path=Theme.settings(),
            image_path_selected=Theme.settings_selected(),
            description="",
            icon=Theme.settings(),
            value=self.fast_forward
        ))

        popup_options.append(GridOrListEntry(
            primary_text=Language.ra_menu(),
            image_path=Theme.settings(),
            image_path_selected=Theme.settings_selected(),
            description="",
            icon=Theme.settings(),
            value=self.ra_menu
        ))

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
            self.send_cmd_to_ra(b'PAUSE_TOGGLE')
            return popup_selection.get_selection().get_value()(popup_selection.get_input())
        else:
            self.send_cmd_to_ra(b'PAUSE_TOGGLE')
            return True