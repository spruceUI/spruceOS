

from display.display import Display
from display.font_purpose import FontPurpose
from themes.theme import Theme


class TextUtils():
    def scroll_string(text, amt, text_available_width):
        if not text:
            return text
        space_width, char_height = Display.get_text_dimensions(
            FontPurpose.LIST, " ")

        text_width, char_height = Display.get_text_dimensions(
            FontPurpose.LIST, text)
        spaces_to_add = ((text_available_width - text_width) // space_width)
        spaces_to_add = max(spaces_to_add, 8)
        text = text + ' ' * spaces_to_add
        amt = amt % len(text)  # Ensure n is within the string length
        return text[amt:] + text[:amt]
