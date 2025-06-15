import json
import os
import shutil
from PIL import Image
from display.font_purpose import FontPurpose
from utils.logger import PyUiLogger


class ThemePatcher():

    # Add properties you want to scale (case-sensitive)
    SCALABLE_KEYS = {"grid1x4","grid3x4","FontSize","gameSelectImgWidth","gameSelectImgHeight","gridGameSelectImgWidth",
                     "gridGameSelectImgHeight","listGameSelectImgWidth","listGameSelectImgHeight","gridMultiRowSelBgResizePadWidth",
                     "gridMultiRowSelBgResizePadHeight","gridMultiRowExtraYPad"}

    @classmethod
    def patch_theme(cls, path, target_width, target_height):
        from display.display import Display
        try:
            background_image = os.path.join(path, "skin","background.png")
            theme_width, theme_height = Display.get_image_dimensions(background_image)
            if(theme_width != 0 and theme_width != target_width):
                PyUiLogger().get_logger().error(f"Patching theme {path}")
                cls.scale_theme(path, theme_width, theme_height, target_width, target_height)
            return True
        except Exception as e:
            PyUiLogger().get_logger().error(f"Failed to process {path}: {e}")
            return False

    @classmethod
    def scale_theme(cls, config_path, theme_width, theme_height, target_width, target_height):
        from display.display import Display
        from themes.theme import Theme
        from devices.device import Device
        scale_width = target_width / theme_width
        scale_height = target_height / theme_height
        scale = min(scale_width, scale_height)

        Display.clear("Theme Patch")
        Display.render_text_centered(f"Theme is missing correctly sized assets so patching",Device.screen_width()//2, Device.screen_height()//2,Theme.text_color_selected(FontPurpose.LIST), purpose=FontPurpose.LIST)
        Display.render_text_centered(f"Patching main assets",Device.screen_width()//2, Device.screen_height()//2 + 100,Theme.text_color_selected(FontPurpose.LIST), purpose=FontPurpose.LIST)
        Display.present()

        cls.patch_folder(os.path.join(config_path,"skin"),
                     os.path.join(config_path,f"skin_{target_width}x{target_height}"),
                     scale)
        
        Display.clear("Theme Patch")
        Display.render_text_centered(f"Theme is missing correctly sized assets so caling",Device.screen_width()//2, Device.screen_height()//2,Theme.text_color_selected(FontPurpose.LIST), purpose=FontPurpose.LIST)
        Display.render_text_centered(f"Patching icons",Device.screen_width()//2, Device.screen_height()//2 + 100,Theme.text_color_selected(FontPurpose.LIST), purpose=FontPurpose.LIST)
        Display.present()

        cls.patch_folder(os.path.join(config_path,"icons"),
                     os.path.join(config_path,f"icons_{target_width}x{target_height}"),
                     scale)
    
        cls.scale_config_json(os.path.join(config_path,"config.json"),
                     os.path.join(config_path,f"config_{target_width}x{target_height}.json"),
                     scale)

    @classmethod
    def patch_folder(cls, input_folder, output_folder, scale):
        PyUiLogger().get_logger().error(f"Patching theme [{input_folder}] to [{input_folder}] with scale factor [{scale}]")
        # Ensure the output directory exists
        os.makedirs(output_folder, exist_ok=True)

        for entry in os.listdir(input_folder):
            input_path = os.path.join(input_folder, entry)
            output_path = os.path.join(output_folder, entry)

            if os.path.isdir(input_path):
                # Recursively patch subfolders
                cls.patch_folder(input_path, output_path, scale)
            elif os.path.isfile(input_path):
                # Process image file
                cls.scale_image(input_path, output_path, scale)

    @staticmethod
    def scale_image(input_file, output_file, scale):
        try:
            with Image.open(input_file) as img:
                new_width = int(img.width * scale)
                new_height = int(img.height * scale)
                resized_img = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
                resized_img.save(output_file)
                PyUiLogger().get_logger().info(f"Scaled and saved: {output_file}")
        except Exception as e:
            # Copy the file instead of scaling if something fails
            try:
                shutil.copyfile(input_file, output_file)
                PyUiLogger().get_logger().warning(f"Scaling failed for {input_file}, copied original instead: {e}")
            except Exception as copy_err:
                PyUiLogger().get_logger().error(f"Failed to copy {input_file} to {output_file}: {copy_err}")    
                        
    @classmethod
    def scale_config_json(cls, config_path, output_config_path, scale):
        try:
            with open(config_path, 'r') as f:
                config = json.load(f)

            scaled_config = cls._scale_json_values(config, scale)

            os.makedirs(os.path.dirname(output_config_path), exist_ok=True)
            with open(output_config_path, 'w') as f:
                json.dump(scaled_config, f, indent=4)

            print(f"Scaled config written to: {output_config_path}")
        except Exception as e:
            print(f"Failed to process JSON config {config_path}: {e}")

    @classmethod
    def _scale_json_values(cls, obj, scale):
        if isinstance(obj, dict):
            return {
                k: cls._scale_json_values(v, scale) if not cls._should_scale_key(k) else cls._scale_if_number(v, scale)
                for k, v in obj.items()
            }
        elif isinstance(obj, list):
            return [cls._scale_json_values(i, scale) for i in obj]
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

    @staticmethod
    def _scale_if_number(value, scale):
        return int(value * scale) if isinstance(value, (int, float)) else value