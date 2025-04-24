import os
import hashlib

# Constants
BASE_ROM_PATH = "/mnt/sdcard/Roms"
SECONDARY_ROM_PATH = "/media/sdcard1/Roms"
ROM_PATHS = [BASE_ROM_PATH, SECONDARY_ROM_PATH]
EMU_BASE_PATH = "/mnt/sdcard/Emu"
CHECKSUM_BASE_PATH = "/mnt/sdcard/Emu/.emu_setup/md5"

def updates_detected(folder_path, collected_files):
    emu_folder = folder_path.replace(BASE_ROM_PATH, EMU_BASE_PATH)
    folder_name = os.path.basename(folder_path)

    if not os.path.isdir(emu_folder):
        return

    # Modify emu files
    for file_name in os.listdir(emu_folder):
        file_path = os.path.join(emu_folder, file_name)
        if not os.path.isfile(file_path):
            continue

        try:
            with open(file_path, 'rb+') as f:
                content = f.read()

                if not collected_files:
                    # Disabling — ensure it starts with {{
                    if not content.startswith(b'{{'):
                        new_content = b'{{' + content.lstrip(b'{')
                        f.seek(0)
                        f.write(new_content)
                        f.truncate()
                else:
                    # Enabling — change starting '{{' to '{'
                    if content.startswith(b'{{'):
                        new_content = b'{' + content[2:]
                        f.seek(0)
                        f.write(new_content)
                        f.truncate()
        except Exception as e:
            print(f"Skipping {file_path}: {e}")

    # Delete cache6.db and cache7.db files from rom directories
    for root_path in ROM_PATHS:
        target_folder = os.path.join(root_path, folder_name)
        if not os.path.isdir(target_folder):
            continue

        for file_name in os.listdir(target_folder):
            if file_name.endswith("cache6.db") or file_name.endswith("cache7.db"):
                try:
                    os.remove(os.path.join(target_folder, file_name))
                except Exception as e:
                    print(f"Failed to delete {file_name}: {e}")

def calculate_checksum(file_names):
    concatenated = ''.join(sorted(file_names)).encode('utf-8')
    return hashlib.md5(concatenated).hexdigest()

def main():
    romset_changed = False

    for folder_name in os.listdir(EMU_BASE_PATH):
        if folder_name.startswith('.'):
            continue

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
            os.makedirs(os.path.dirname(checksum_file), exist_ok=True)
            with open(checksum_file, 'w') as f:
                f.write(checksum)
            updates_detected(os.path.join(BASE_ROM_PATH, folder_name), collected_files)
            romset_changed = True

    print(f"{romset_changed}")

if __name__ == "__main__":
    main()
