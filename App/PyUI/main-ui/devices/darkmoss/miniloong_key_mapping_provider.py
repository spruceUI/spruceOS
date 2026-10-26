from controller.controller_inputs import ControllerInput
from controller.key_watcher_controller import HorizontalStickAxis, VerticalStickAxis


class MiniloongKeyMappingProvider:
    """Buttons from a plain dict, plus the stick axes as d-pad input.

    Same retrogame_joypad driver as the RGB30, so the same -1800..1800 axis
    range and deadzone. The pad reports a second pair of axes the Pocket 1 has
    no stick for; mapping them costs nothing.
    """

    ABS_X = 0
    ABS_Y = 1
    ABS_RX = 3
    ABS_RY = 4
    EV_ABS = 3
    DEADZONE = 900

    def __init__(self, key_mappings):
        self.key_mappings = key_mappings
        self.stick_axes = {
            self.ABS_X: HorizontalStickAxis(ControllerInput.LEFT_STICK_LEFT, ControllerInput.LEFT_STICK_RIGHT),
            self.ABS_Y: VerticalStickAxis(ControllerInput.LEFT_STICK_UP, ControllerInput.LEFT_STICK_DOWN),
            self.ABS_RX: HorizontalStickAxis(ControllerInput.RIGHT_STICK_LEFT, ControllerInput.RIGHT_STICK_RIGHT),
            self.ABS_RY: VerticalStickAxis(ControllerInput.RIGHT_STICK_UP, ControllerInput.RIGHT_STICK_DOWN),
        }

    def get_mapped_events(self, key_event):
        if key_event.event_type != self.EV_ABS:
            return self.key_mappings.get(key_event)

        axis = self.stick_axes.get(key_event.code)
        if axis is None:
            return None
        return axis.get_mapped_events(key_event.value, self.DEADZONE)
