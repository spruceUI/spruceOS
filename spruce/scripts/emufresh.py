import os
import hashlib

def update_config(folder_path, collected_files):
    emu_folder = folder_path.replace("/mnt/sdcard/Roms", "/mnt/sdcard/Emu")
    folder_name = os.path.basename(folder_path)

    if not os.path.isdir(emu_folder):
        return

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

def calculate_checksum(file_names):
    concatenated = ''.join(sorted(file_names)).encode('utf-8')
    return hashlib.md5(concatenated).hexdigest()

def main():
    base_rom_path = "/mnt/sdcard/Roms/"
    checksum_base_path = "/mnt/sdcard/Emu/.emu_setup/md5/"
    romset_changed = False

    for folder_name in os.listdir(base_rom_path):
        if folder_name.startswith('.'):
            continue
        
        folder_path = os.path.join(base_rom_path, folder_name)
        if not os.path.isdir(folder_path):
            continue

        collected_files = []
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
        checksum_file = os.path.join(checksum_base_path, f"{folder_name}.md5")

        existing_checksum = None
        if os.path.exists(checksum_file):
            with open(checksum_file, 'r') as f:
                existing_checksum = f.read().strip()

        if checksum != existing_checksum:
            os.makedirs(os.path.dirname(checksum_file), exist_ok=True)
            with open(checksum_file, 'w') as f:
                f.write(checksum)
            update_config(folder_path, collected_files)
            romset_changed = True
    print(f"{romset_changed}")
    
if __name__ == "__main__":
    main()
