

from controller.controller import Controller


class ButtonListener:
    def __init__(self):
        pass

    def start(self):
        while(True):
            Controller.get_input()
            if(Controller.last_controller_input is not None):
                print(Controller.last_input())