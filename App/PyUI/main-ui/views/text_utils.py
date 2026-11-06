

from display.display import Display
from display.font_purpose import FontPurpose


class TextUtils():
    def scroll_string(text, amt, text_available_width):
        if not text:
            return text
        space_width, char_height = Display.get_space_dimensions()

        text_width, char_height = Display.get_text_dimensions(
            FontPurpose.LIST, text)
        spaces_to_add = ((text_available_width - text_width) // space_width)
        spaces_to_add = max(spaces_to_add, 8)
        text = text + ' ' * spaces_to_add
        amt = amt % len(text)  # Ensure n is within the string length
        return text[amt:] + text[:amt]

    @staticmethod
    def scroll_string_centered(text, amt, text_available_width):
        if not text or text_available_width is None:
            return text

        space_width, _ = Display.get_space_dimensions()
        if space_width <= 0:
            return text

        text_width, _ = Display.get_text_dimensions(FontPurpose.LIST, text)
        spaces_to_add = max(
            8,
            max(0, text_available_width - text_width + space_width - 1) // space_width + 8
        )
        leading_spaces = spaces_to_add // 2
        text = " " * leading_spaces + text + " " * (spaces_to_add - leading_spaces)
        amt %= len(text)
        return text[amt:] + text[:amt]

    @staticmethod
    def scroll_string_chars(text, amt, max_chars, padding_spaces_count = 8):
        if not text or max_chars <= 0:
            return text

        # If it already fits, return as-is
        if len(text) <= max_chars:
            return text

        text += ' ' * padding_spaces_count
        # Loop scroll offset safely
        amt = amt % len(text)

        # Duplicate string to allow wraparound slicing
        doubled = text + text

        return doubled[amt:amt + max_chars]