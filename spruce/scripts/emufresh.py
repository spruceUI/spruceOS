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

def check_checksum(folder_path, collected_files, checksum_base_path, romset_changed):
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

def scan_dirs(base_rom_path, checksum_base_path):
    romset_status = False

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

        if check_checksum(folder_name, collected_files, checksum_base_path, romset_status):
            romset_status = True
    return romset_status

def main():
    first_rom_path = "/mnt/sdcard/Roms/"
    second_rom_path = "/media/sdcard1/Roms"
    checksum_base_path_sd1 = "/mnt/sdcard/Emu/.emu_setup/md5/flip/sd1"
    checksum_base_path_sd2 = "/mnt/sdcard/Emu/.emu_setup/md5/flip/sd2"
    first_romset_changed = scan_dirs(first_rom_path, checksum_base_path_sd1)
    second_romset_changed = scan_dirs(second_rom_path, checksum_base_path_sd2)
    
    if first_romset_changed or second_romset_changed:
        romset_changed = True
    else:
        romset_changed = False
    
    print(f"{romset_changed}")

if __name__ == "__main__":
    main()
