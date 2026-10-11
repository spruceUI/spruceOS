

from controller.controller import Controller
from controller.controller_inputs import ControllerInput
from display.display import Display


class UserPrompt():

    @staticmethod
    def prompt_yes_no(title, messages, use_fallback_fonts_for_missing_glyphs=False):
        messages.extend(["","A = Yes, B = No"])
        while(True):
            Display.clear(title)
            Display.display_message_multiline(messages,
                                              use_fallback_fonts_for_missing_glyphs=use_fallback_fonts_for_missing_glyphs)
            Display.present()
            if(Controller.get_input()):
                if(Controller.last_input() == ControllerInput.A):
                    return True
                elif(Controller.last_input() == ControllerInput.B):
                    return False
