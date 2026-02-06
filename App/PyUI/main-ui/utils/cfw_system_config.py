import json

class CfwSystemConfig():
    _data = {}
    _config_path = None

    @classmethod
    def init(cls, config_path):
        cls._config_path = config_path
        cls.reload_config()

    @classmethod
    def reload_config(cls):
        try:
            if(cls._config_path is not None):
                with open(cls._config_path, 'r', encoding='utf-8') as f:
                    cls._data = json.load(f)
        except Exception:
            cls._data = {}

    @classmethod
    def save_config(cls):
        """Save the current _data back to the JSON file."""
        if cls._config_path is None:
            return
        with open(cls._config_path, 'w', encoding='utf-8') as f:
            json.dump(cls._data, f, indent=4)

    @classmethod
    def get_categories(cls):
        """Return a list of all category names under menuOptions."""
        return list(cls._data.get('menuOptions', {}).keys())

    @classmethod
    def get_menu_options(cls, category):
        """Return the menu options. If category is given, return only that category."""
        menu_options = cls._data.get('menuOptions', {})
        if category:
            return menu_options.get(category, {})
        return menu_options

    @classmethod
    def get_menu_option(cls, category, name):
        """Return a specific menu option by category and name, or None if not found."""
        return cls._data.get('menuOptions', {}).get(category, {}).get(name)

    @classmethod
    def set_menu_option(cls, category, name, selected_value):
        """
        Update a specific menu option's selected value by category and name.
        """
        menu_options = cls._data.get('menuOptions', {}).get(category, {})
        if name in menu_options:
            menu_options[name]['selected'] = selected_value
            cls.save_config()
            cls.reload_config()
        else:
            # Optional: log or raise if not found
            pass

    @classmethod
    def get_selected_value(cls, category, name):
        """Return the selected value of a menu option, or None if not found."""
        option = cls.get_menu_option(category, name)
        if option:
            return option.get('selected')
        return None
