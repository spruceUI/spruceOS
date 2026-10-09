import re

from display.display import Display
from menus.games.utils import raproxy_cli
from menus.language.language import Language
from menus.settings import settings_menu
from themes.theme import Theme
from views.grid_or_list_entry import GridOrListEntry


class PendingAwardsMenu(settings_menu.SettingsMenu):

    def __init__(self):
        super().__init__()
        Display.display_message(Language.label("loadingCheevos", "Loading..."))
        self.awards = self.load_awards()

    @staticmethod
    def load_awards():
        out = raproxy_cli.run("pending-awards") or ""
        awards = []
        for line in out.strip().splitlines():
            parts = [p.strip() for p in re.sub(r"^\d+\.\s*", "", line).split(" | ")]
            if len(parts) >= 2:
                awards.append(parts)
        return awards

    def reload_options(self):
        return False

    def build_options_list(self):
        option_list = [
            GridOrListEntry(
                primary_text=parts[1],
                value_text=None,
                image_path=None,
                image_path_selected=None,
                description=" | ".join([parts[0]] + parts[2:]),
                icon=Theme.cheevos_icon(),
                value=lambda input_value: None
            )
            for parts in self.awards
        ]

        if not option_list:
            option_list.append(
                GridOrListEntry(
                    primary_text=Language.label("noPendingAwards", "No pending awards"),
                    value_text=None,
                    image_path=None,
                    image_path_selected=None,
                    description=None,
                    icon=None,
                    value=lambda input_value: None
                )
            )

        return option_list
