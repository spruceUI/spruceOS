#!/usr/bin/env python3
"""
Fix display imports to use conditional import from display/__init__.py
Changes: from display.display import Display -> from display import Display
"""

import os
import re
from pathlib import Path

# Root directory to search
ROOT_DIR = Path(__file__).parent / "main-ui"

# Pattern to match
OLD_PATTERN = r'^from display\.display import Display'
NEW_IMPORT = 'from display import Display'

def fix_file(filepath):
    """Fix imports in a single file"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()

        # Check if file contains the old pattern
        if re.search(OLD_PATTERN, content, re.MULTILINE):
            # Replace the import
            new_content = re.sub(OLD_PATTERN, NEW_IMPORT, content, flags=re.MULTILINE)

            # Write back
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(new_content)

            return True

        return False

    except Exception as e:
        print(f"Error processing {filepath}: {e}")
        return False

def main():
    """Find and fix all Python files with old import pattern"""
    fixed_count = 0

    # Walk through all Python files
    for py_file in ROOT_DIR.rglob("*.py"):
        # Skip the display files themselves
        if 'display.py' in py_file.name or 'display_pygame.py' in py_file.name:
            continue

        if fix_file(py_file):
            print(f"Fixed: {py_file.relative_to(ROOT_DIR)}")
            fixed_count += 1

    print(f"\n✓ Fixed {fixed_count} files")

if __name__ == "__main__":
    main()
