
import os
from utils.image_utils import ImageUtils
from PIL import Image
from utils.logger import PyUiLogger


class PilImageUtils(ImageUtils):
    def convert_from_jpg_to_qoi(self, jpg_path, png_path):
        with Image.open(jpg_path) as img:
            img.save(png_path, "QOI")

    def convert_from_jpg_to_png(self, jpg_path, png_path):
        with Image.open(jpg_path) as img:
            img.save(png_path, "PNG")

    def shrink_image_if_needed(self, input_path, output_path, width, height):
        img = Image.open(input_path)
        actual_width, actual_height = img.size

        # Only shrink if necessary
        if actual_width > width or actual_height > height:
            aspect_ratio = actual_width / actual_height
            if actual_width / width > actual_height / height:
                # Width is the limiting factor
                new_width = width
                new_height = int(width / aspect_ratio)
            else:
                # Height is the limiting factor
                new_height = height
                new_width = int(height * aspect_ratio)

            img = img.resize((new_width, new_height), Image.LANCZOS)
            img.save(output_path)
            PyUiLogger().get_logger().info(f"Scaled: {input_path} to {output_path} ({actual_width}x{actual_height}) -> {new_width}x{new_height}")
            return True
        else:
            # Image is already small enough; just copy
            # shutil.copyfile(input_path, output_path)
            PyUiLogger().get_logger().info(
                f"Skipping as already small enough: {input_path} → {output_path} ({actual_width}x{actual_height})"
            )
            return False
            
    def resize_image(self, input_path, output_path, width, height):
        img = Image.open(input_path)
        actual_width, actual_height = img.size

        aspect_ratio = actual_width / actual_height
        if actual_width / width > actual_height / height:
            # Width is the limiting factor
            new_width = width
            new_height = int(width / aspect_ratio)
        else:
            # Height is the limiting factor
            new_height = height
            new_width = int(height * aspect_ratio)

        img = img.resize((new_width, new_height), Image.LANCZOS)
        img.save(output_path)
        PyUiLogger().get_logger().info(f"Scaled: {input_path} to {output_path} -> {new_width}x{new_height}")

    def get_image_dimensions(self, path):
        try:
            with Image.open(path) as img:
                return img.width, img.height
        except Exception as e:
            PyUiLogger().get_logger().warning(f"Unable to get image dimensions for {path}")
            return 0,0
        
        
    def convert_from_png_to_qoi(self, png_path, qoi_path=None):
        """
        Converts a PNG file to a 32-bit RGBA QOI using ffmpeg.
        The QOI will be in the same directory with the same basename.
        """
        if png_path.lower().endswith(".qoi"):
            PyUiLogger().get_logger().info(f"{png_path} is already a qoi")
            return
        if not png_path.lower().endswith(".png"):
            PyUiLogger().get_logger().warning(f"{png_path} is not a png")

        if(qoi_path is None):
            qoi_path = os.path.splitext(png_path)[0] + ".qoi"

        # Open PNG
        with Image.open(png_path) as img:
            # Ensure 32-bit RGBA
            img = img.convert("RGBA")
            # Save as QOI
            img.save(qoi_path, format="QOI")

        PyUiLogger().get_logger().info(f"Converted {png_path} ==> {qoi_path}")

        return qoi_path