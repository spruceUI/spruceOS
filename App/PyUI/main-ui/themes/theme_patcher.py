import json
import os
import shutil
import time
from devices.device import Device
from utils.cached_exists import CachedExists
from utils.logger import PyUiLogger


class ThemePatcher():
    _last_display_time = 0
    # Add properties you want to scale (case-sensitive)
    SCALABLE_KEYS = {"grid1x4","grid3x4","FontSize","gameSelectImgWidth","gameSelectImgHeight","gridGameSelectImgWidth",
                     "gridGameSelectImgHeight","listGameSelectImgWidth","listGameSelectImgHeight","gridMultiRowSelBgResizePadWidth",
                     "gridMultiRowSelBgResizePadHeight","gridMultiRowExtraYPad", "topBarInitialXOffset","gridMultiRowImageYOffset",
                     "singleRowGridTextYOffset","multiRowGridTextYOffset","carouselSystemXPad",
                     "gridSystemImageYOffset","gridSystemSelectImgWidth","listSystemSelectImgWidth","carouselSystemSelectPrimaryImgWidth",
                     "gridSystemSelectImgHeight","listSystemSelectImgHeight","carouselSystemAdditionalYOffset"}
    WIDTH_SCALABLE_KEYS = {"gameSystemSelectColCount","carouselSystemExternalXPad",
                           "carouselSystemFixedWidth","mainMenuColCount","gameSelectColCount", 
                           "gameSystemSelectCarouselColCount",
                           "carouselSystemSelectedOffset","carouselSystemFixedWidth", "carouselSystemFixedSelectedWidth" # These might not belong here
                           }
    HEIGHT_SCALABLE_KEYS = {"gameSystemSelectRowCount", "gameSelectRowCount"}
    ASPECT_RATIO_RESET_KEYS = {
        "recentsEnabled": True,
    }

    @classmethod
    def convert_to_qoi(cls, path):
        from display.display import Display
        PyUiLogger().get_logger().info(f"Checking if theme is patched")
        if(cls.contains_qoi(path)):
            PyUiLogger().get_logger().info(f"Theme was patched")
            return False

        Display.clear("Patching Theme")
        Display.display_message("Patching theme to faster assets")
        for dirpath, dirnames, filenames in os.walk(path):
            for filename in filenames:
                if filename.lower().endswith(".png"):
                    try:
                        full_path = os.path.join(dirpath, filename)
                        cls.convert_png_to_qoi(full_path)      
                    except Exception as e:
                        PyUiLogger().get_logger().warning(f"Unable to convert {full_path} : {e}")

        return True   
       
    @classmethod
    def contains_qoi(cls,path):
        """Return True if any .qoi file exists under path (including subdirectories)."""
        try:
            for entry in os.scandir(path):
                if entry.is_file(follow_symlinks=False):
                    # Check last 4 characters, case-insensitive
                    if entry.name[-4:].lower() == ".qoi":
                        return True
                elif entry.is_dir(follow_symlinks=False):
                    # Recurse into subdirectory
                    if cls.contains_qoi(entry.path):
                        return True
        except PermissionError:
            pass  # Skip directories we can't access
        return False        

    @classmethod
    def convert_png_to_qoi(cls,png_path):
        from display.display import Display
        now = time.time()
        if now - cls._last_display_time >= 1.0:
            Display.display_message(f"Converting {os.path.basename(png_path)}")
            cls._last_display_time = now
        image_utils = Device.get_device().get_image_utils()
        image_utils.convert_from_png_to_qoi(png_path)


    @classmethod
    def patch_theme(cls, path, target_width, target_height):
        from display.display import Display
        try:
            background_image = os.path.join(path, "skin","background.png")
            if(not os.path.exists(background_image)):
                background_image = os.path.join(path, "skin","background.qoi")

            theme_width, theme_height = Display.get_image_dimensions(background_image)
            PyUiLogger.get_logger().debug(f"Theme background size: {theme_width}x{theme_height}, Target size: {target_width}x{target_height}")
            if(theme_width != 0 and theme_width != target_width):
                cls.scale_theme(path, theme_width, theme_height, target_width, target_height)
            return True
        except Exception as e:
            PyUiLogger().get_logger().exception(f"Failed to process {path}: {e}")
            return False

    @classmethod
    def scale_theme(cls, config_path, theme_width, theme_height, target_width, target_height):
        from display.display import Display
        CachedExists.clear()
        scale_width = target_width / theme_width
        scale_height = target_height / theme_height
        scale = min(scale_width, scale_height)
        # TODO care about height multiplier at some point
        PyUiLogger.get_logger().info(f"Scale Width: {scale_width}, Scale Height: {scale_height}")
        if(scale_width > scale_height):
            width_multiplier = ((scale_width-scale_height) / scale_height) + 1
            height_multiplier = 1.0
        else:
            height_multiplier = ((scale_height-scale_width) / scale_width) + 1
            width_multiplier = 1.0  

        aspect_ratio_reset = abs(scale_width - scale_height) > 1e-6

        PyUiLogger().get_logger().info(f"Patching theme {config_path} from {theme_width}x{theme_height} to {target_width}x{target_height} w/ a scale factor of {scale}")

        Display.clear("Theme Patch")
        Display.display_message_multiline([
            f"Theme is missing correctly sized assets so patching",
            f"Scale factor is {scale}"
            f"Patching main assets"
        ])
        Display.present()

        cls.patch_folder(os.path.join(config_path,"skin"),
                     os.path.join(config_path,f"skin_{target_width}x{target_height}"),
                     scale,
                     theme_width, theme_height, target_width, target_height)
        
        Display.clear("Theme Patch")
        Display.display_message_multiline([
            f"Theme is missing correctly sized assets so patching",
            f"Scale factor is {scale}"
            f"Patching icons"
        ])
        Display.present()

        if(os.path.exists(os.path.join(config_path,"icons"))):
            cls.patch_folder(os.path.join(config_path,"icons"),
                        os.path.join(config_path,f"icons_{target_width}x{target_height}"),
                        scale,
                        theme_width, theme_height, target_width, target_height)
    
        cls.scale_config_json(os.path.join(config_path,"config.json"),
                     os.path.join(config_path,f"config_{target_width}x{target_height}.json"),
                     scale,
                     width_multiplier,
                     height_multiplier,
                     aspect_ratio_reset)

    @classmethod
    def patch_folder(cls, input_folder, output_folder, scale, theme_width, theme_height, target_width, target_height):
        from display.display import Display
        PyUiLogger().get_logger().info(f"Patching theme [{input_folder}] to [{input_folder}] with scale factor [{scale}]")
        # Ensure the output directory exists
        os.makedirs(output_folder, exist_ok=True)

        for entry in os.listdir(input_folder):
            input_path = os.path.join(input_folder, entry)
            output_path = os.path.join(output_folder, entry)

            if os.path.isdir(input_path):
                # Recursively patch subfolders
                cls.patch_folder(input_path, output_path, scale, theme_width, theme_height, target_width, target_height)
            elif os.path.isfile(input_path):
                now = time.time()
                if now - cls._last_display_time >= 1.0:
                    Display.display_message_multiline([
                        f"Patching {os.path.basename(input_path)}",
                        f"Scale factor is {scale}"
                    ])
                    cls._last_display_time = now
                # Process image file
                cls.scale_image(input_path, output_path, scale, theme_width, theme_height, target_width, target_height)

    @staticmethod
    def scale_image(input_file, output_file, scale, theme_width, theme_height, target_width, target_height):
        if os.path.exists(output_file):
            PyUiLogger().get_logger().info(f"Scaled version of {output_file} already exists, skipping scaling.")
        else:
            image_utils = Device.get_device().get_image_utils()
            try:
                img_width ,img_height = image_utils.get_image_dimensions(input_file)
                new_width = int(img_width * scale)
                new_height = int(img_height * scale)
                preserve_aspect_ratio = True
                is_icon = "icons" in input_file.lower()

                if(img_width == theme_width and img_height != theme_height and not is_icon):
                    new_width = target_width
                    preserve_aspect_ratio = False

                if(img_height == theme_height and img_width != theme_width and not is_icon):
                    new_height = target_height
                    preserve_aspect_ratio = False

                image_utils.resize_image(input_file, output_file, new_width, new_height,preserve_aspect_ratio=preserve_aspect_ratio)

                if not os.path.exists(output_file):
                    # Means non image -- should this be raised as an error as part of resize?
                    shutil.copyfile(input_file, output_file)

            except Exception as e:
                # Copy the file instead of scaling if something fails
                try:
                    shutil.copyfile(input_file, output_file)
                    PyUiLogger().get_logger().warning(f"Scaling failed for {input_file}, copied original instead: {e}")
                except Exception as copy_err:
                    PyUiLogger().get_logger().exception(f"Failed to copy {input_file} to {output_file}: {copy_err}")    
                        
    @classmethod
    def scale_config_json(cls, config_path, output_config_path, scale, width_multiplier, height_multiplier, aspect_ratio_reset):
        try:
            with open(config_path, 'r') as f:
                config = json.load(f)

            scaled_config = cls._scale_json_values(config, scale, width_multiplier, height_multiplier, aspect_ratio_reset)

            os.makedirs(os.path.dirname(output_config_path), exist_ok=True)
            with open(output_config_path, 'w') as f:
                json.dump(scaled_config, f, indent=4)

            PyUiLogger.get_logger().info(f"Scaled config written to: {output_config_path}")
        except Exception as e:
            PyUiLogger().get_logger().exception(f"Failed to process JSON config {config_path}: {e}")    

    @classmethod
    def _scale_json_values(cls, obj, scale, width_multiplier, height_multiplier, aspect_ratio_reset):
        if isinstance(obj, dict):
            new_dict = {}
            for k, v in obj.items():

                if k in cls.ASPECT_RATIO_RESET_KEYS:
                    new_dict[k] = cls.ASPECT_RATIO_RESET_KEYS[k]
                elif cls._should_scale_based_on_width(k) and abs(width_multiplier - 1.0) > 1e-6:
                    PyUiLogger.get_logger().info(f"Scaled {k} based on width_multiplier of {width_multiplier}")
                    new_dict[k] = cls._scale_if_number(v, width_multiplier)
                elif cls._should_scale_based_on_height(k) and abs(height_multiplier - 1.0) > 1e-6:
                    PyUiLogger.get_logger().info(f"Scaled {k} based on height_multiplier of {height_multiplier}")
                    new_dict[k] = cls._scale_if_number(v, height_multiplier)  
                elif cls._should_scale_key(k):
                    new_dict[k] = cls._scale_if_number(v, scale)

                else:
                    new_dict[k] = cls._scale_json_values(v, scale, width_multiplier, height_multiplier, aspect_ratio_reset)

            return new_dict

        elif isinstance(obj, list):
            return [cls._scale_json_values(i, scale, width_multiplier, height_multiplier, aspect_ratio_reset) for i in obj]

        else:
            return obj

    @classmethod
    def _should_scale_key(cls, key):
        should_scale = key in cls.SCALABLE_KEYS or key.endswith("size") or key.endswith("Size")
        if(should_scale):
            PyUiLogger.get_logger().info(f"Scaling {key}")
        else:
            PyUiLogger.get_logger().info(f"Not scaling {key}")
        return should_scale

    @classmethod
    def _should_scale_based_on_width(cls, key):
        should_scale = key in cls.WIDTH_SCALABLE_KEYS 
        if(should_scale):
            PyUiLogger.get_logger().info(f"Width Scaling {key}")
        else:
            PyUiLogger.get_logger().info(f"Not scaling {key}")
        return should_scale
    
    @classmethod
    def _should_scale_based_on_height(cls, key):
        should_scale = key in cls.HEIGHT_SCALABLE_KEYS 
        if(should_scale):
            PyUiLogger.get_logger().info(f"Height Scaling {key}")
        else:
            PyUiLogger.get_logger().info(f"Not scaling {key}")
        return should_scale
    
    

    @staticmethod
    def _scale_if_number(value, scale):
        return int(value * scale) if isinstance(value, (int, float)) else value
    
    