from controller.controller_inputs import ControllerInput
from menus.apps.trimui_input_helpers import TrimuiInputHelpers
from views.grid_or_list_entry import GridOrListEntry
from views.view_creator import ViewCreator
from views.view_type import ViewType


class TrimuiFnSettingsApp:
    def run(self, _input=None):
        while True:
            options = self._build_options()
            view = ViewCreator.create_view(
                view_type=ViewType.ICON_AND_DESC,
                top_bar_text="Fn & Switch Settings",
                options=options,
                selected_index=0,
            )
            picked = view.get_selection(
                [
                    ControllerInput.A,
                    ControllerInput.B,
                    ControllerInput.DPAD_LEFT,
                    ControllerInput.DPAD_RIGHT,
                    ControllerInput.L1,
                    ControllerInput.R1,
                ]
            )
            if picked.get_input() == ControllerInput.B:
                return
            if picked.get_input() in (
                ControllerInput.A,
                ControllerInput.DPAD_LEFT,
                ControllerInput.DPAD_RIGHT,
                ControllerInput.L1,
                ControllerInput.R1,
            ):
                picked.get_selection().get_value()(picked.get_input())

    def _build_options(self):
        return [
            self._toggle_entry(
                "Joystick mode (D-pad as stick)",
                TrimuiInputHelpers.is_joystick_mode(),
                lambda enabled: TrimuiInputHelpers.set_joystick_mode(enabled),
            ),
            self._toggle_entry(
                "Quiet mode",
                TrimuiInputHelpers.is_quiet_mode(),
                lambda enabled: TrimuiInputHelpers.set_quiet_mode(enabled),
            ),
            self._toggle_entry(
                "Silent mode (mute speaker)",
                TrimuiInputHelpers.is_silent_mode(),
                lambda enabled: TrimuiInputHelpers.set_silent_mode(enabled),
            ),
            self._toggle_entry(
                "RGB LED",
                TrimuiInputHelpers.is_led_enabled(),
                lambda enabled: TrimuiInputHelpers.set_led_enabled(enabled),
            ),
        ]

    def _toggle_entry(self, label, is_on, setter):
        state = "On" if is_on else "Off"

        def adjust(input_value):
            if input_value in (
                ControllerInput.DPAD_LEFT,
                ControllerInput.L1,
            ):
                setter(False)
            elif input_value in (
                ControllerInput.DPAD_RIGHT,
                ControllerInput.R1,
                ControllerInput.A,
            ):
                setter(True)

        return GridOrListEntry(
            primary_text=label,
            value_text=f"<    {state}    >",
            image_path=None,
            image_path_selected=None,
            description=None,
            icon=None,
            value=adjust,
        )
