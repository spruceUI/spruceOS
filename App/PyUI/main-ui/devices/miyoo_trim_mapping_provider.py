from controller.controller_inputs import ControllerInput
from controller.key_state import KeyState
from controller.key_watcher_controller_dataclasses import InputResult, KeyEvent

DEADZONE=16000
class MiyooTrimKeyMappingProvider:
    def __init__(self):
        self.key_mappings = {}  
        self.key_mappings[KeyEvent(1, 304, 0)] = [InputResult(ControllerInput.B, KeyState.RELEASE)]
        self.key_mappings[KeyEvent(1, 304, 1)] = [InputResult(ControllerInput.B, KeyState.PRESS)]
        self.key_mappings[KeyEvent(1, 305, 0)] = [InputResult(ControllerInput.A, KeyState.RELEASE)]  
        self.key_mappings[KeyEvent(1, 305, 1)] = [InputResult(ControllerInput.A, KeyState.PRESS)]   
        self.key_mappings[KeyEvent(1, 308, 0)] = [InputResult(ControllerInput.X, KeyState.RELEASE)]  
        self.key_mappings[KeyEvent(1, 308, 1)] = [InputResult(ControllerInput.X, KeyState.PRESS)]  
        self.key_mappings[KeyEvent(1, 307, 0)] = [InputResult(ControllerInput.Y, KeyState.RELEASE)]  
        self.key_mappings[KeyEvent(1, 307, 1)] = [InputResult(ControllerInput.Y, KeyState.PRESS)]  


        self.key_mappings[KeyEvent(3, 17, -1)] = [InputResult(ControllerInput.DPAD_UP, KeyState.PRESS)]
        self.key_mappings[KeyEvent(3, 17, 1)] = [InputResult(ControllerInput.DPAD_DOWN, KeyState.PRESS)]
        self.key_mappings[KeyEvent(3, 17, 0)] = [InputResult(ControllerInput.DPAD_UP, KeyState.RELEASE), InputResult(ControllerInput.DPAD_DOWN, KeyState.RELEASE)]
        self.key_mappings[KeyEvent(3, 16, -1)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.PRESS)]
        self.key_mappings[KeyEvent(3, 16, 1)] = [InputResult(ControllerInput.DPAD_RIGHT, KeyState.PRESS)]
        self.key_mappings[KeyEvent(3, 16, 0)] = [InputResult(ControllerInput.DPAD_LEFT, KeyState.RELEASE), InputResult(ControllerInput.DPAD_RIGHT, KeyState.RELEASE)]


        self.key_mappings[KeyEvent(1, 311, 0)] = [InputResult(ControllerInput.R1, KeyState.RELEASE)]  
        self.key_mappings[KeyEvent(1, 311, 1)] = [InputResult(ControllerInput.R1, KeyState.PRESS)]  
        self.key_mappings[KeyEvent(3, 5, 0)] = [InputResult(ControllerInput.R2, KeyState.RELEASE)]  
        self.key_mappings[KeyEvent(3, 5, 255)] = [InputResult(ControllerInput.R2, KeyState.PRESS)]  
        self.key_mappings[KeyEvent(1, 310, 0)] = [InputResult(ControllerInput.L1, KeyState.RELEASE)]  
        self.key_mappings[KeyEvent(1, 310, 1)] = [InputResult(ControllerInput.L1, KeyState.PRESS)]  
        self.key_mappings[KeyEvent(3, 2, 0)] = [InputResult(ControllerInput.L2, KeyState.RELEASE)]  
        self.key_mappings[KeyEvent(3, 2, 255)] = [InputResult(ControllerInput.L2, KeyState.PRESS)]  

        self.key_mappings[KeyEvent(1, 316, 0)] = [InputResult(ControllerInput.MENU, KeyState.RELEASE)]  
        self.key_mappings[KeyEvent(1, 316, 1)] = [InputResult(ControllerInput.MENU, KeyState.PRESS)]
        self.key_mappings[KeyEvent(1, 315, 0)] = [InputResult(ControllerInput.START, KeyState.RELEASE)]
        self.key_mappings[KeyEvent(1, 315, 1)] = [InputResult(ControllerInput.START, KeyState.PRESS)]  
        self.key_mappings[KeyEvent(1, 314, 0)] = [InputResult(ControllerInput.SELECT, KeyState.RELEASE)]   
        self.key_mappings[KeyEvent(1, 314, 1)] = [InputResult(ControllerInput.SELECT, KeyState.PRESS)]   
        
    def get_mapped_events(self, key_event):
        mappings = self.key_mappings.get(key_event)
        if mappings is None and key_event.event_type == 3:
            # LEFT STICK Y
            if key_event.code == 1:
                if key_event.value < -DEADZONE:
                    return [
                        InputResult(ControllerInput.LEFT_STICK_UP, KeyState.PRESS)
                    ]
                elif key_event.value > DEADZONE:
                    return [
                        InputResult(ControllerInput.LEFT_STICK_DOWN, KeyState.PRESS)
                    ]
                else:
                    return [
                        InputResult(ControllerInput.LEFT_STICK_UP, KeyState.RELEASE),
                        InputResult(ControllerInput.LEFT_STICK_DOWN, KeyState.RELEASE),
                    ]
            # LEFT STICK X 
            if key_event.code == 0:
                if key_event.value < -DEADZONE:
                    return [
                        InputResult(ControllerInput.LEFT_STICK_LEFT, KeyState.PRESS)
                    ]
                elif key_event.value > DEADZONE:
                    return [
                        InputResult(ControllerInput.LEFT_STICK_RIGHT, KeyState.PRESS)
                    ]
                else:
                    return [
                        InputResult(ControllerInput.LEFT_STICK_LEFT, KeyState.RELEASE),
                        InputResult(ControllerInput.LEFT_STICK_RIGHT, KeyState.RELEASE),
                    ]

        return mappings