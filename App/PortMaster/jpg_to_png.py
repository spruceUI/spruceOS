from PIL import Image
import sys
import os

def convert_jpg_to_png(input_path, output_path=None):
    if not os.path.exists(input_path):
        print(f"[ERROR] File not found: {input_path}")
        return

    try:
        with Image.open(input_path) as img:
            print(f"Opened image. Format: {img.format}, Size: {img.size}")
            if not output_path:
                base = os.path.splitext(input_path)[0]
                output_path = base + ".png"
            img.save(output_path, "PNG")
            print(f"Converted '{input_path}' to '{output_path}'")
    except Exception as e:
        print(f"[ERROR] Failed to convert image: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python jpg_to_png.py input.jpg [output.png]")
    else:
        input_file = sys.argv[1]
        output_file = sys.argv[2] if len(sys.argv) > 2 else None
        convert_jpg_to_png(input_file, output_file)
