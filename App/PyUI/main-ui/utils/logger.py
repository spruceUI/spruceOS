import logging
from logging.handlers import RotatingFileHandler
import os
import sys

from utils.etension_preserving_rotating_file_handler import ExtensionPreservingRotatingFileHandler

class StreamToLogger:
    """Redirect writes to a logger."""
    def __init__(self, logger, level, stream=None):
        import sys
        self.logger = logger
        self.level = level
        self.stream = stream or getattr(sys, "__stdout__", sys.stdout)
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
    def init(cls, log_dir, logger_name):
        if cls._logger is not None:
            return cls._logger

        try:
            cls.rotate_logs(log_dir)  # Ensure logs are rotated before initializing logger

            logger = logging.getLogger(logger_name)
            logger.setLevel(logging.DEBUG)

            if not logger.handlers:
                formatter = logging.Formatter(
                    "%(asctime)s - %(filename)s:%(lineno)d - %(funcName)s - %(levelname)s - %(message)s"
                )

                # Console handler (explicit stdout)
                console_handler = logging.StreamHandler(sys.__stdout__)
                console_handler.setLevel(logging.DEBUG)
                console_handler.setFormatter(formatter)

                # File handler
                file_handler = ExtensionPreservingRotatingFileHandler(
                    os.path.join(log_dir, "pyui.log"),
                    maxBytes=1024 * 1024,
                    backupCount=5
                )
                file_handler.setLevel(logging.DEBUG)
                file_handler.setFormatter(formatter)

                logger.addHandler(console_handler)
                logger.addHandler(file_handler)

            # Redirect stdout/stderr
            sys.stdout = StreamToLogger(logger, logging.INFO, sys.__stdout__)
            sys.stderr = StreamToLogger(logger, logging.ERROR, sys.__stderr__)

            cls._logger = logger
            return logger

        except Exception as e:
            # --- Fallback logger ---
            fallback = logging.getLogger(f"{logger_name}_fallback")
            fallback.setLevel(logging.DEBUG)

            if not fallback.handlers:
                formatter = logging.Formatter(
                    "%(asctime)s - %(levelname)s - %(message)s"
                )

                out_handler = logging.StreamHandler(sys.__stdout__)
                err_handler = logging.StreamHandler(sys.__stderr__)

                out_handler.setLevel(logging.INFO)
                err_handler.setLevel(logging.ERROR)

                out_handler.setFormatter(formatter)
                err_handler.setFormatter(formatter)

                fallback.addHandler(out_handler)
                fallback.addHandler(err_handler)

            fallback.error("Logger initialization failed, using fallback logger", exc_info=True)

            cls._logger = fallback
            return fallback

    @staticmethod
    def rotate_logs(log_dir):
        try:
            base = os.path.join(log_dir, "pyui")
            ext = ".log"
            max_backups = 5

            # Remove oldest
            oldest = "%s.%d%s" % (base, max_backups, ext)
            if os.path.exists(oldest):
                os.remove(oldest)

            # Shift backups up
            for i in range(max_backups - 1, 0, -1):
                src = "%s.%d%s" % (base, i, ext)
                dst = "%s.%d%s" % (base, i + 1, ext)
                if os.path.exists(src):
                    os.rename(src, dst)

            # Rotate current log
            current = "%s%s" % (base, ext)
            first = "%s.1%s" % (base, ext)
            if os.path.exists(current):
                os.rename(current, first)

        except Exception as e:
            print("Error rotating logs (likely RO filesystem): %s" % e)


    @classmethod
    def get_logger(cls):
        return cls._logger
    
