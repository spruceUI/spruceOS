

from abc import ABC


class View(ABC):
    def __init__(self):
        pass

    def is_alphabetized(self,options: list):
        texts = [opt.get_primary_text() for opt in options]
        return texts == sorted(texts)

    def view_finished(self):
        #Callers should always call this one the view
        #is done with so it can be cleaned up as needed
        pass

    def first_letter_of(self, option):
        # Entries expose their label through get_primary_text(); RomGridOrListEntry
        # stores it as display_name and has no primary_text attribute at all.
        text = option.get_primary_text() or ""
        return text[0].lower() if text else ""

    def calculate_amount_to_move_by(self, amount, skip_by_letter):
        # --- Step 1: If amount is not 1 or -1, jump to next/previous letter ---
        # Only list_view guards its own empty list, so bounds-check here for the rest.
        if not self.options or not (0 <= self.selected < len(self.options)):
            return amount

        if amount != 1 and amount != -1 and skip_by_letter:
            current_letter = self.first_letter_of(self.options[self.selected])
            new_selected = self.selected

            if amount > 1:
                # Move forward to the first option with a different starting letter
                for i in range(self.selected + 1, len(self.options)):
                    if self.first_letter_of(self.options[i]) != current_letter:
                        new_selected = i
                        break
                else:
                    # Wrap around to the first option if none found
                    new_selected = 0
            elif amount < -1:
                # Move backward to the first option with a different starting letter
                for i in range(self.selected - 1, -1, -1):
                    if self.first_letter_of(self.options[i]) != current_letter:
                        new_selected = i
                        break
                else:
                    # Wrap around to the last option if none found
                    new_selected = len(self.options) - 1

            # Adjust amount to jump to the new index
            amount = new_selected - self.selected

        return amount