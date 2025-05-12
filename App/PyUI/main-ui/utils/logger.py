import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import shutil
import sys

class StreamToLogger:
    """Redirect writes to a logger."""
    def __init__(self, logger, level):
        self.logger = logger
        self.level = level
        self._buffer = ""

    def write(self, message):
        message = message.strip()
        if message:
            self.logger.log(self.level, message)

    def flush(self):
        pass  # Not needed

class PyUiLogger:
    _logger = None  # Class-level cache for the logger

    @classmethod
    def init(cls, file_path, logger_name):
        if cls._logger is not None:
            return cls._logger

        cls.rotate_logs()  # Ensure logs are rotated before initializing logger

        logger = logging.getLogger(logger_name)
        logger.setLevel(logging.DEBUG)

        if not logger.handlers:
            formatter = logging.Formatter(
                "%(asctime)s - %(filename)s:%(lineno)d - %(funcName)s - %(levelname)s - %(message)s"
            )

            # Console handler
            console_handler = logging.StreamHandler()
            console_handler.setLevel(logging.DEBUG)
            console_handler.setFormatter(formatter)

            # File handler
            file_handler = RotatingFileHandler(file_path,
                maxBytes=10 * 1024,  # 1MB file size limit
                backupCount=5               # Keep up to 5 backup files)
            )
            file_handler.setLevel(logging.DEBUG)
            file_handler.setFormatter(formatter)

            logger.addHandler(console_handler)
            logger.addHandler(file_handler)
            
        # Redirect stdout and stderr to logger
        sys.stdout = StreamToLogger(logger, logging.INFO)
        sys.stderr = StreamToLogger(logger, logging.ERROR)

        cls._logger = logger
        return cls._logger
    
    @staticmethod
    def rotate_logs():
        # Perform log rotation before initializing the logger
        log_path = "/mnt/SDCARD/Saves/spruce/pyui.log"
        backup_path = "/mnt/SDCARD/Saves/spruce/pyui.log.5"

        # Rotate logs manually before starting
        if os.path.exists(backup_path):
            os.remove(backup_path)
        for i in range(4, 0, -1):
            src = f"{log_path}.{i}" if i > 1 else log_path
            dest = f"{log_path}.{i + 1}"
            if os.path.exists(src):
                os.rename(src, dest)

        # Optionally, delete the pyui-5.log if it exists
        if os.path.exists(f"{log_path}.5"):
            os.remove(f"{log_path}.5")
            
    @classmethod
    def get_logger(cls):
        return cls._logger
    
