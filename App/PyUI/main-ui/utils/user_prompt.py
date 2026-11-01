

from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from display.display import Display
from menus.common import symbols


class UserPrompt():

    @staticmethod
    def prompt_yes_no(title, messages):
        messages.extend(["", f"{symbols.BTN_A} Yes, {symbols.BTN_B} No"])
        while(True):
            Display.clear(title)
            Display.display_message_multiline(messages)
            Display.present()
            if(Controller.get_input()):
                if(Controller.last_input() == ControllerInput.A):
                    return True
                elif(Controller.last_input() == ControllerInput.B):
                    return False
