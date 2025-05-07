import os
import time

class RomUtils:
    def __init__(self, roms_path):
        self.roms_path = roms_path

    def get_roms_path(self):
        return self.roms_path
    
    def build_cache(self):
        for entry in os.scandir(self.roms_path):
            print(f"building cache for {entry}")
            if entry.is_dir(follow_symlinks=False) and not entry.name.startswith('.'):
                system = entry.name
                roms = self.scan_for_roms(system)
                
                rom_list_path = os.path.join(entry.path, '.rom_list.txt')
                with open(rom_list_path, 'w', encoding='utf-8') as f:
                    for rom_path in roms:
                        f.write(f"{rom_path}\n")
                print(f"Wrote cache to {rom_list_path}")

    def read_rom_list(self, system):
        rom_list_path = os.path.join(self.roms_path, system, '.rom_list.txt')
        
        if not os.path.exists(rom_list_path):
            return []  # Or raise an exception, depending on your use case
        
        with open(rom_list_path, 'r', encoding='utf-8') as f:
            return [line.strip() for line in f if line.strip()]
    
    def scan_for_roms(self, system):
        directory = os.path.join(self.roms_path, system)
        valid_files = sorted(
            entry.path for entry in os.scandir(directory)
            if entry.is_file(follow_symlinks=False)
            and not entry.name.startswith('.')
            and not entry.name.endswith(('.xml', '.txt', '.db'))
        )
        return valid_files

    def get_roms(self, system):
        start_time = time.time()
        result = self.scan_for_roms(system)
        elapsed = time.time() - start_time
        return result