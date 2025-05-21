import json
import os

class MiyooAppConfig:
    def __init__(self, json_path):
        if not os.path.exists(json_path):
            raise FileNotFoundError(f"Config file not found: {json_path}")
        
        with open(json_path, 'r') as f:
            data = json.load(f)
        
        self.label = data.get("label")
        self.icontop = data.get("icontop")
        self.icon = data.get("icon")
        self.launch = data.get("launch")
        self.folder = os.path.dirname(json_path)

        if(self.launch == "launch.sh"):
            self.launch = os.path.join(self.folder,self.launch)

        self.description = data.get("description")

    def get_label(self):
        return self.label

    def get_icontop(self):
        return self.icontop

    def get_icon(self):
        return self.icon

    def get_launch(self):
        return self.launch

    def get_description(self):
        return self.description
    
    def get_folder(self):
        return self.folder
