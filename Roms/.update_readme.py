import json
import os

# Iterate over each console directory
for console in os.listdir('.'):
    json_path = os.path.join(console, 'games.json')
    readme_path = os.path.join(console, 'README.md')
    
    # Process only if games.json exists in the directory
    if os.path.exists(json_path):
        with open(json_path) as f:
            games = json.load(f)
        
        # Begin building the README content
        content = f"# Check out these games for {console}!\n\n"
        
        for game in games:
            content += f'<img width="123" src="{game["cover"]}">\n'
            content += '<div style="background-color:#eeeeee">\n'
            content += f'<details>\n  <summary>{game["name"]}</summary>\n  <br>\n'
            content += '  <i>Recommended by:</i>\n  <br>\n'
            
            # Add each collaborator's GitHub link and avatar
            for user in game['recommended_by']:
                content += f'  <a href="https://github.com/{user}/">\n'
                content += f'  <img src="https://avatars.githubusercontent.com/{user}?s=24" align="left"/></a> {user}\n  <br>\n'
            
            content += '  <br></details></div>\n\n'
        
        # Write the README.md for the specific console
        with open(readme_path, 'w') as f:
            f.write(content)

print("README.md files generated for each console.")
