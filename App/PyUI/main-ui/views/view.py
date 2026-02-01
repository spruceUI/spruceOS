

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

    def calculate_amount_to_move_by(self, amount, skip_by_letter):
        # --- Step 1: If amount is not 1 or -1, jump to next/previous letter ---
        if amount != 1 and amount != -1 and skip_by_letter:
            current_letter = self.options[self.selected].primary_text[0].lower()
            new_selected = self.selected

            if amount > 1:
                # Move forward to the first option with a different starting letter
                for i in range(self.selected + 1, len(self.options)):
                    if self.options[i].primary_text[0].lower() != current_letter:
                        new_selected = i
                        break
                else:
                    # Wrap around to the first option if none found
                    new_selected = 0
            elif amount < -1:
                # Move backward to the first option with a different starting letter
                for i in range(self.selected - 1, -1, -1):
                    if self.options[i].primary_text[0].lower() != current_letter:
                        new_selected = i
                        break
                else:
                    # Wrap around to the last option if none found
                    new_selected = len(self.options) - 1

            # Adjust amount to jump to the new index
            amount = new_selected - self.selected

        return amount