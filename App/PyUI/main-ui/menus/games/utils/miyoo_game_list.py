import os
import re
import xml.etree.ElementTree as ET

from utils.logger import PyUiLogger

class GameEntry:
    def __init__(self, game_id, source, path, image, name):
        self.id = game_id
        self.source = source
        self.path = path
        self.image = image
        self.name = name

    def __repr__(self):
        return f"<GameEntry name='{self.name}' file='{self.path}'>"


class MiyooGameList:
    def __init__(self, xml_file):
        self.games_by_file_name = {}
        self._load(xml_file)

    def _load(self, xml_file):
        if not os.path.isfile(xml_file):
            return
        try:
            # Read the entire file content into memory
            with open(xml_file, "r", encoding="utf-8") as f:
                content = f.read().strip()

            # Ensure there is at least a newline at the end of the file
            # This avoids ElementTree thinking there are multiple root elements
            if not content.endswith('\n'):
                content += '\n'

            # Fix invalid & that are not part of an entity (e.g., &amp;, &lt;, etc.)
            content = re.sub(r'&(?![a-zA-Z]+;|#\d+;)', '&amp;', content)
            
            # Parse the XML from the cleaned string
            root = ET.fromstring(content)

            base_dir = os.path.dirname(xml_file)
            for game in root.findall('game'):
                game_id = game.get('id')
                source = game.get('source')

                path = game.findtext('path')
                image = game.findtext('image')
                name = game.findtext('name')

                if path.startswith('./'):
                    file_name = path[2:]
                else:
                    file_name = path

                # Make image path relative to the XML file's directory
                image_path = os.path.join(base_dir, image[2:] if image.startswith('./') else image)
                entry = GameEntry(game_id, source, path, image_path, name)
                self.games_by_file_name[file_name] = entry

        except Exception as e:
            import traceback
            PyUiLogger.get_logger().error(f"Error loading XML file '{xml_file}': {e}")
            PyUiLogger.get_logger().error(traceback.format_exc())


    def get_by_file_path(self, file_path):
        # Normalize the path and find the portion after "Roms/"
        parts = file_path.split("/Roms/", 1)
        if len(parts) < 2:
            return None  # No "Roms/" in path
        rel_path = parts[1]  # e.g. "FC/subFolder1/subFolder2/game.txt"

        # Split into components
        components = rel_path.split("/")

        # Remove the system folder (e.g., "FC") and begin recursive search
        for i in range(1, len(components)):
            sub_path = "/".join(components[i:])
            if sub_path in self.games_by_file_name:
                return self.games_by_file_name[sub_path]

        # Finally, check just the filename as a fallback
        file_name = components[-1]
        return self.games_by_file_name.get(file_name)