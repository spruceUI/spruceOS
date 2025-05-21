import os
import hashlib
import logging

# Constants
BASE_ROM_PATH = "/mnt/SDCARD/Roms"
SECONDARY_ROM_PATH = "/media/sdcard1/Roms"
ROM_PATHS = [BASE_ROM_PATH, SECONDARY_ROM_PATH]
EMU_BASE_PATH = "/mnt/SDCARD/Emu"
CHECKSUM_BASE_PATH = "/mnt/SDCARD/Emu/.emu_setup/md5"

# Set up logging
logging.basicConfig(
    filename="/mnt/SDCARD/Saves/spruce/emufresh.py.log",  # Log to a file
    level=logging.DEBUG,         # Log all levels of messages
    format="%(asctime)s - %(levelname)s - %(message)s",
    filemode='w' #overwrite the log on each run
)

def pico_files_present():
    logging.debug("Checking for PICO-8 files.")
    check_paths = [
        os.path.join(EMU_BASE_PATH, "PICO8", "bin"),
        "/mnt/SDCARD/BIOS",
        "/media/sdcard1/BIOS"
    ]

    for path in check_paths:
        if (os.path.isfile(os.path.join(path, "pico8.dat")) and
            os.path.isfile(os.path.join(path, "pico8_64"))):
            logging.info(f"PICO-8 files found in {path}.")
            return True

    logging.warning("PICO-8 files not found in any of the paths.")
    return False

def is_system_showing(folder_path):
    emu_folder = folder_path.replace(BASE_ROM_PATH, EMU_BASE_PATH)
    config_path = os.path.join(emu_folder, "config.json")
    if os.path.isfile(config_path):
        try:
            with open(config_path, 'rb') as f:
                content = f.read()
                return not content.startswith(b'{{')
        except Exception as e:
            logging.error(f"Error reading {config_path}: {e}")
            return False
    else:
        logging.warning(f"Config file {config_path} not found.")
        return True  

def updates_detected(folder_path, collected_files):
    emu_folder = folder_path.replace(BASE_ROM_PATH, EMU_BASE_PATH)
    folder_name = os.path.basename(folder_path)

    if not os.path.isdir(emu_folder):
        logging.warning(f"Emulator folder {emu_folder} does not exist.")
        return

    config_path = os.path.join(emu_folder, "config.json")
    if os.path.isfile(config_path):
        try:
            with open(config_path, 'rb+') as f:
                content = f.read()

                if not collected_files:
                    if not content.startswith(b'{{'):
                        new_content = b'{{' + content.lstrip(b'{')
                        f.seek(0)
                        f.write(new_content)
                        f.truncate()
                        logging.info(f"Config file {config_path} modified to start with '{{{{'.")
                else:
                    if content.startswith(b'{{'):
                        new_content = b'{' + content[2:]
                        f.seek(0)
                        f.write(new_content)
                        f.truncate()
                        logging.info(f"Config file {config_path} modified to start with '{{'.")
        except Exception as e:
            logging.error(f"Error updating {config_path}: {e}")

    # Delete cache files
    for root_path in ROM_PATHS:
        target_folder = os.path.join(root_path, folder_name)
        if not os.path.isdir(target_folder):
            continue

        for suffix in ["_cache6.db", "_cache7.db"]:
            cache_file = os.path.join(target_folder, folder_name + suffix)
            if os.path.exists(cache_file):
                try:
                    os.remove(cache_file)
                    logging.info(f"Deleted cache file {cache_file}.")
                except Exception as e:
                    logging.error(f"Failed to delete {cache_file}: {e}")

def calculate_checksum(file_names):
    concatenated = ''.join(sorted(file_names)).encode('utf-8')
    checksum = hashlib.md5(concatenated).hexdigest()
    return checksum

def main():
    romset_changed = False

    for folder_name in os.listdir(EMU_BASE_PATH):
        if folder_name.startswith('.'):
            continue
        elif "PICO8" == folder_name:
            currently_showing = is_system_showing(os.path.join(BASE_ROM_PATH, folder_name))
            should_show = pico_files_present()
            logging.info(f"PICO8: currently_showing={currently_showing}, should_show={should_show}")
            if currently_showing != should_show:
                logging.info(f"System changed: {folder_name}")
                updates_detected(os.path.join(BASE_ROM_PATH, folder_name), should_show)
                romset_changed = True
        else: 
            collected_files = []
            for root_path in ROM_PATHS:
                folder_path = os.path.join(root_path, folder_name)
                if not os.path.isdir(folder_path):
                    continue

                for sub_name in os.listdir(folder_path):
                    sub_path = os.path.join(folder_path, sub_name)
                    if os.path.isdir(sub_path) and sub_name == 'Imgs':
                        continue
                    if os.path.isfile(sub_path):
                        if (
                            sub_name.startswith('.') or
                            sub_name.endswith('.xml') or
                            sub_name.endswith('.txt') or
                            sub_name.endswith('.db')
                        ):
                            continue

                        collected_files.append(sub_name)

            checksum = calculate_checksum(collected_files)
            checksum_file = os.path.join(CHECKSUM_BASE_PATH, f"{folder_name}.md5")

            existing_checksum = None
            if os.path.exists(checksum_file):
                with open(checksum_file, 'r') as f:
                    existing_checksum = f.read().strip()

            if checksum != existing_checksum:
                logging.info(f"System changed: {folder_name}")
                os.makedirs(os.path.dirname(checksum_file), exist_ok=True)
                with open(checksum_file, 'w') as f:
                    f.write(checksum)
                updates_detected(os.path.join(BASE_ROM_PATH, folder_name), collected_files)
                romset_changed = True

    logging.info(f"Romset changed: {romset_changed}")
    print(f"{romset_changed}")

if __name__ == "__main__":
    main()
