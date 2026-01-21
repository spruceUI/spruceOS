import json
import sys

def merge_selected(old, new, path=""):
    """
    Recursively copy 'selected' values and valid 'overrides' from old into new.
    Logs every update.
    """
    if not isinstance(old, dict) or not isinstance(new, dict):
        return

    for key, old_val in old.items():
        if key not in new:
            print(f"'{key}' is not in the new config")
            continue

        new_val = new[key]
        current_path = f"{path}/{key}" if path else key

        if key == "selected":
            if old_val is None:
                continue

            options = new.get("options")

            # Normal option-based settings
            if isinstance(options, list):
                if old_val in options:
                    print(f"Copying '{current_path}': {new_val} -> {old_val}")
                    new[key] = old_val
                else:
                    print(f"Value is no longer valid in latest config '{current_path}': {old_val}")

            # Free-text settings (no options key at all)
            elif "options" not in new:
                print(f"Copying freeText '{current_path}': {new_val} -> {old_val}")
                new[key] = old_val
        else:
            merge_selected(old_val, new_val, current_path)


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <existing_config> <new_config>")
        sys.exit(1)

    existing_config = sys.argv[1]
    new_config = sys.argv[2]

    # Load JSON files
    with open(existing_config, "r", encoding="utf-8") as f:
        old_json = json.load(f)

    with open(new_config, "r", encoding="utf-8") as f:
        new_json = json.load(f)

    # Merge selected values
    merge_selected(old_json, new_json)

    # Write merged result back into new_config
    with open(new_config, "w", encoding="utf-8") as f:
        json.dump(new_json, f, indent=4)

    print(f"Merged selected values written to {new_config}")

if __name__ == "__main__":
    main()
