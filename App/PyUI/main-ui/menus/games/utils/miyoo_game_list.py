import os
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
            tree = ET.parse(xml_file)
            root = tree.getroot()
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
            PyUiLogger.get_logger().error(f"Error loading XML file '{xml_file}': {e}")

    def get_by_file_name(self, file_name):
        return self.games_by_file_name.get(file_name)
