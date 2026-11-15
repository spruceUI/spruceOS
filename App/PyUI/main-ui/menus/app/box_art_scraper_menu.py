from devices.device import Device
from display.display import Display
from display.on_screen_keyboard import OnScreenKeyboard
from menus.language.language import Language
from menus.settings.list_of_options_selection_menu import ListOfOptionsSelectionMenu
from utils.boxart.box_art_scraper import BoxArtScraper
from utils.boxart.screenscraper import LOGIN, ScreenScraper, ScreenScraperError
from utils.user_prompt import UserPrompt


class BoxArtScraperMenu:
    """The Boxart Scraper app: download missing box art, and sign in to ScreenScraper.

    Signed in (and with spruce's ScreenScraper developer credentials in the build), box art
    comes from ScreenScraper, with libretro for whatever it misses; otherwise from libretro.
    """

    DOWNLOAD = "download"
    SIGN_IN = "sign_in"
    SIGN_OUT = "sign_out"

    def run(self):
        while True:
            client = ScreenScraper()
            options = [(self.DOWNLOAD, Language.label("downloadMissingBoxart", "Download missing box art"))]
            if client.has_dev_credentials():
                if client.signed_in():
                    options.append((self.SIGN_OUT, Language.label("screenscraperSignedInAs", "ScreenScraper: {user} (sign out)")
                                    .replace("{user}", client.username)))
                else:
                    options.append((self.SIGN_IN, Language.label("screenscraperSignIn", "Sign in to ScreenScraper")))

            choice = ListOfOptionsSelectionMenu().get_selected_option_index(
                [label for _, label in options], Language.label("boxartScraperTitle", "Boxart Scraper"))
            if choice is None:
                return
            action = options[choice][0]
            if action == self.DOWNLOAD:
                BoxArtScraper().scrape_boxart()
            elif action == self.SIGN_IN:
                self.sign_in()
            elif action == self.SIGN_OUT:
                self.sign_out(client.username)

    def sign_in(self):
        if not Device.get_device().is_wifi_enabled():
            Display.display_message(Language.label("wifiMustBeConnected", "Wifi must be connected"), 2000)
            return
        username = OnScreenKeyboard().get_input(Language.label("screenscraperUsername", "ScreenScraper user name"))
        if not username:
            return
        password = OnScreenKeyboard().get_input(Language.label("screenscraperPassword", "ScreenScraper password"))
        if not password:
            return

        Display.display_message(Language.label("screenscraperChecking", "Checking your ScreenScraper account..."))
        client = ScreenScraper()
        client.username, client.password = username.strip(), password
        try:
            client.start()
        except ScreenScraperError as e:
            if e.kind == LOGIN:
                message = Language.label("screenscraperWrongLogin", "ScreenScraper did not accept that user name and password.")
            else:
                message = Language.label("screenscraperCheckFailed", "Could not check the account with ScreenScraper. Try again later.")
            Display.display_message(message, 3000)
            return
        ScreenScraper.save_login(client.username, client.password)
        Display.display_message(
            Language.label("screenscraperSignedIn", "Signed in as {user}. Box art now comes from ScreenScraper.")
            .replace("{user}", client.username), 3000)

    def sign_out(self, username):
        if UserPrompt.prompt_yes_no(
                Language.label("screenscraperSignOutTitle", "Sign out of ScreenScraper"),
                [Language.label("screenscraperSignOutPrompt", "Sign out {user}? Box art will come from libretro.")
                 .replace("{user}", username)]):
            ScreenScraper.sign_out()
