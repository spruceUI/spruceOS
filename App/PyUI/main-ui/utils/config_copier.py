

from pathlib import Path
import shutil

from utils.logger import PyUiLogger


class ConfigCopier:

    @classmethod
    def ensure_config(cls, file_path, default_config_file):
        """
        Ensures that a config file exists at the given file_path.
        If it does not, copies 'config.json' from the script's directory to that location.
        """
        try:
            dest = Path(file_path)
            if dest.exists() and dest.stat().st_size > 0:
                return  # Nothing to do

            if not default_config_file.exists():
                PyUiLogger.get_logger().error(f"{default_config_file} does not exist")
                raise FileNotFoundError(f"Source config file not found: {default_config_file}")

            # Create parent directories if necessary
            dest.parent.mkdir(parents=True, exist_ok=True)

            PyUiLogger.get_logger().info(f"Copying {default_config_file} to {file_path}")
            # Copy the file
            shutil.copy2(default_config_file, dest)
        except Exception as e:
            # Log the exception with stack trace
            PyUiLogger.get_logger().exception(f"Failed to ensure config for {file_path}: {e}")
