
import math
import os
import shutil
import subprocess
import sys
from utils.image_utils import ImageUtils
from utils.logger import PyUiLogger


class FfmpegImageUtils(ImageUtils):

    def convert_type(self, input_path, output_path):
        try:
            subprocess.run([
                "ffmpeg",
                "-y",           # overwrite if exists
                "-i", input_path,
                output_path
            ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError as e:
            PyUiLogger().get_logger().error(f"Error converting {input_path} to {output_path}: {e}")

    def convert_from_jpg_to_qoi(self,jpg_path, qoi_path):
       self.convert_type(jpg_path,qoi_path)


    def convert_from_jpg_to_png(self,jpg_path, png_path):
       self.convert_type(jpg_path,png_path)

    def get_image_dimensions_ffmpeg(self, path: str):
        """
        Returns (width, height) of an image using ffmpeg only.
        Works without ffprobe.
        """
        try:
            # ffmpeg prints the resolution line, e.g. "Stream #0: Video: png, 1920x1080 ..."
            result = subprocess.run(
                ["ffmpeg", "-v", "info", "-i", path, "-f", "null", "-"],
                capture_output=True, text=True
            )
            # Combine stdout and stderr (metadata usually appears on stderr)
            output = result.stderr + result.stdout

            # Find pattern like "1920x1080"
            import re
            match = re.search(r'(\d{2,5})x(\d{2,5})', output)
            if match:
                width, height = map(int, match.groups())
                return width, height

            return sys.maxsize, sys.maxsize

        except Exception as e:
            PyUiLogger.get_logger().exception(f"ffmpeg dimension detection failed for {path}")
            return sys.maxsize, sys.maxsize
        
    def shrink_image_if_needed(self,input_path, output_path, max_width, max_height):
        
        actual_width,actual_height = self.get_image_dimensions_ffmpeg(input_path)
        if actual_width > max_width or actual_height > max_height:
            temp_path = output_path + ".tmp.png"
            
            scale_filter = f"scale='min({max_width},iw)':'min({max_height},ih)':force_original_aspect_ratio=decrease"
            try:
                subprocess.run([
                    "ffmpeg",
                    "-y",
                    "-i", input_path,
                    "-vf", scale_filter,
                    "-frames:v", "1",
                    "-update", "1",
                    temp_path
                ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                # Replace original file
                shutil.move(temp_path, output_path)
                PyUiLogger().get_logger().info(f"Scaled: {input_path} → {output_path} to {max_width}x{max_height}")
            except subprocess.CalledProcessError as e:
                PyUiLogger().get_logger().error(f"Error resizing {input_path}: {e}")
                # Clean up temp file if it exists
                if os.path.exists(temp_path):
                    os.remove(temp_path)
            
            return True
        else:
            PyUiLogger().get_logger().info(
                f"Skipping as already small enough: {input_path} → {output_path} ({actual_width}x{actual_height})"
            )
            return False

    def resize_image(self, input_path, output_path, max_width, max_height, preserve_aspect_ratio=True, target_alpha_channel=None):
        """
        Resize the image to fit within max_width/max_height preserving aspect ratio.
        This WILL enlarge the image if it is smaller than the requested bounds.
        Uses ffmpeg and writes to a temporary file before moving to output_path.
        """
        try:
            actual_width, actual_height = self.get_image_dimensions(input_path)
            if actual_width == 0 or actual_height == 0:
                PyUiLogger().get_logger().warning(f"Can't determine dimensions for {input_path}; skipping resize.")
                return

            if(preserve_aspect_ratio):
                # compute scale factor allowing both shrink and enlarge
                scale_w = float(max_width) / float(actual_width)
                scale_h = float(max_height) / float(actual_height)
                scale = min(scale_w, scale_h)

                # compute new dimensions (ensure at least 1)
                new_width = int(math.floor(actual_width * scale))
                new_height = int(math.floor(actual_height * scale))
            else:
                new_width = max_width
                new_height = max_height

            # If already the desired size, just copy (or move) the file
            if new_width == actual_width and new_height == actual_height:
                # If output_path differs from input_path, copy; otherwise nothing to do
                if os.path.abspath(input_path) != os.path.abspath(output_path):
                    shutil.copy2(input_path, output_path)
                    PyUiLogger().get_logger().info(f"Copied without scaling: {input_path} → {output_path} ({new_width}x{new_height})")
                else:
                    PyUiLogger().get_logger().info(f"No resizing needed for {input_path} ({new_width}x{new_height})")
                return

            # Use a temp file to avoid "cannot overwrite input" problems
            tmp_output = output_path + ".tmp.png"


            if(target_alpha_channel is None):                
                ffmpeg_cmd = [
                    "ffmpeg",
                    "-y",                 # overwrite temp if exists
                    "-i", input_path,
                    "-vf", f"scale={new_width}:{new_height}",
                    "-pix_fmt", "rgba",
                    tmp_output
                ]
            else:
                ffmpeg_cmd = [
                    "ffmpeg",
                    "-i", input_path,
                    "-vf", f"scale={new_width}:{new_height},format=rgba,colorchannelmixer=aa={target_alpha_channel}",
                    tmp_output
                ]

            subprocess.run(ffmpeg_cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            # Move temp file to final destination (atomic on same filesystem)
            shutil.move(tmp_output, output_path)
            PyUiLogger().get_logger().info(f"Resized: {input_path} → {output_path} -> {new_width}x{new_height}")

        except subprocess.CalledProcessError as e:
            PyUiLogger().get_logger().error(f"Error resizing {input_path}: {e}")
            # cleanup temp file if present
            try:
                if os.path.exists(tmp_output):
                    os.remove(tmp_output)
            except Exception:
                pass
        except Exception as e:
            PyUiLogger().get_logger().error(f"Unexpected error resizing {input_path}: {e}")
            try:
                if os.path.exists(tmp_output):
                    os.remove(tmp_output)
            except Exception:
                pass

    def get_image_dimensions(self,path):
        """
        Get image width and height using ffmpeg only (no ffprobe).
        Returns (width, height) or (0,0) on failure.
        """
        try:
            # Run ffmpeg in quiet mode, output info about first frame
            cmd = [
                "ffmpeg",
                "-i", path,
                "-v", "error",
                "-select_streams", "v:0",
                "-show_entries", "stream=width,height",
                "-of", "csv=p=0:s=x"
            ]
            # Actually, the above is ffprobe syntax. For pure ffmpeg we need another trick:
            cmd = ["ffmpeg", "-i", path]
            result = subprocess.run(cmd, capture_output=True, text=True)
            stderr = result.stderr

            # ffmpeg prints something like: Stream #0:0: Video: png, 800x600, ...
            import re
            m = re.search(r"Video:.* (\d+)x(\d+)", stderr)
            if m:
                width = int(m.group(1))
                height = int(m.group(2))
                return width, height
            return 0, 0
        except Exception as e:
            PyUiLogger().get_logger().info(f"Error getting dimens of {path} : {e}")
            return 0, 0

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
        PyUiLogger().get_logger().info(f"Converting {png_path} to qoi")

        if(qoi_path is None):
            qoi_path = os.path.splitext(png_path)[0] + ".qoi"

        # Call ffmpeg to convert PNG → 32-bit RGBA QOI
        subprocess.run([
            "ffmpeg",
            "-y",                  # overwrite output
            "-i", png_path,        # input file
            "-pix_fmt", "rgba",    # 32-bit RGBA
            "-frames:v", "1",      # only one frame
            qoi_path               # output file
        ], check=True)

        PyUiLogger().get_logger().info(f"Converted {png_path} ==> {qoi_path}")

        return qoi_path
