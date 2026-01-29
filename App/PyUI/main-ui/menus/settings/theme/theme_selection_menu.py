
import os
from controller.controller_inputs import ControllerInput
from devices.device import Device
from utils.logger import PyUiLogger
from utils.py_ui_config import PyUiConfig
from views.grid_or_list_entry import GridOrListEntry
from views.selection import Selection
from views.view_creator import ViewCreator
from views.view_type import ViewType


class ThemeSelectionMenu:
    def __init__(self):
        pass

    def get_selected_option_index(self, options, title):
        selected = Selection(None, None, 0)
        option_list = []
        theme_dir = PyUiConfig.get("themeDir")
        for index, opt in enumerate(options):
            png_path = os.path.join(theme_dir,opt,"preview.png")
            image_path = png_path
            if(not os.path.exists(image_path)):
                qoi_path = os.path.join(theme_dir,opt,"preview.qoi")
                image_path = qoi_path
            PyUiLogger.get_logger().info(f"{opt} : {image_path}")
            option = GridOrListEntry(
                    primary_text=opt,
                    value=index,
                    image_path=image_path
                )
            option_list.append(
                option
            )
            if(opt == Device.get_device().get_system_config().get_theme()):
                selected = Selection(option, None, index)

        #convert to text and desc and show the theme desc
        #maybe preview too if theyre common
        view = ViewCreator.create_view(
            view_type=ViewType.TEXT_AND_IMAGE,
            top_bar_text=title,
            options=option_list,
            selected_index=selected.get_index())

        accepted_inputs = [ControllerInput.A, ControllerInput.B]

        while (True):
            selected = view.get_selection(accepted_inputs)
            if (ControllerInput.A == selected.get_input()):
                return selected.get_selection().get_value()
            elif (ControllerInput.B == selected.get_input()):
                return None
