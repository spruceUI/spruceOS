

import os

from themes.theme import Theme


class AppUtils:

    @staticmethod
    def get_icon(app_folder, icon_path_from_config):
        icon_priority = []
        if(icon_path_from_config is not None):
            icon_priority.append(AppUtils._convert_to_theme_version_of_icon(icon_path_from_config))
            icon_priority.append(icon_path_from_config)
            if(app_folder is not None):
                icon_priority.append(os.path.join(app_folder,icon_path_from_config))

        if(app_folder is not None):
            icon_priority.append(os.path.join(app_folder,"icon.png"))
    
        icon_priority.append(Theme.get_cfw_default_icon(icon_path_from_config))

        return AppUtils.get_first_existing_path(icon_priority)

    @staticmethod
    def _convert_to_theme_version_of_icon( icon_path):
        return Theme.get_app_icon(os.path.basename(icon_path))

    @staticmethod
    def get_first_existing_path(file_priority_list):
        for path in file_priority_list:
            try:
                if path and os.path.isfile(path):
                    return path
            except Exception:
                pass
        return None 