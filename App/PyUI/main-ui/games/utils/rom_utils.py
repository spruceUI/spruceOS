import os

class RomUtils:
    def __init__(self, roms_path):
        self.roms_path = roms_path

    def get_roms_path(self):
        return self.roms_path
    
    def get_roms(self, system):
        # Construct the full directory path
        directory = os.path.join(self.roms_path, system)
        
        # List to store valid files
        valid_files = []
        
        # Iterate through the directory
        for filename in os.listdir(directory):
            filepath = os.path.join(directory, filename)
            
            # Skip folders and excluded file types or filenames starting with '.'
            if os.path.isdir(filepath):
                continue
            if filename.endswith(('.xml', '.txt', '.db')) or filename.startswith('.'):
                continue
            
            # Add valid file to the list
            valid_files.append(filepath)
            print(f"Added {filepath}")
        
        valid_files.sort()
        
        return valid_files