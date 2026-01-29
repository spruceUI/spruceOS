
import os


class RomFileNameUtils:
    @staticmethod
    def get_rom_name_without_extensions(game_system, file_path) -> str:
        # Remove all known extensions from the filename
        base_name = os.path.splitext(os.path.basename(file_path))[0]
        if(game_system is None):
            # TODO will create issues for pico 8 boxart potentially
            # But better than crashing for now
            return base_name
        ext_list = game_system.game_system_config.get_extlist()
        while True:
            next_base, next_ext = os.path.splitext(base_name)
            if next_ext.lower() in ext_list:
                base_name = next_base
            else:
                break
        return base_name
