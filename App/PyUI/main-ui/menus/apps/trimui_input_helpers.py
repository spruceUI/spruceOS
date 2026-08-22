import os


class TrimuiInputHelpers:
    INPUT_DIR = "/tmp/trimui_inputd"
    NO_DPAD = f"{INPUT_DIR}/input_no_dpad"
    DPAD_TO_JOYSTICK = f"{INPUT_DIR}/input_dpad_to_joystick"
    MUTED_FLAG = "/tmp/system/muted"
    LED_ENABLE = "/tmp/system/enable_led"

    @classmethod
    def ensure_input_dir(cls):
        os.makedirs(cls.INPUT_DIR, exist_ok=True)

    @classmethod
    def is_joystick_mode(cls) -> bool:
        return os.path.exists(cls.NO_DPAD) and os.path.exists(cls.DPAD_TO_JOYSTICK)

    @classmethod
    def set_joystick_mode(cls, enabled: bool):
        cls.ensure_input_dir()
        if enabled:
            open(cls.NO_DPAD, "a").close()
            open(cls.DPAD_TO_JOYSTICK, "a").close()
        else:
            for path in (cls.NO_DPAD, cls.DPAD_TO_JOYSTICK):
                if os.path.exists(path):
                    os.remove(path)

    @classmethod
    def is_silent_mode(cls) -> bool:
        return os.path.exists(cls.MUTED_FLAG)

    @classmethod
    def set_silent_mode(cls, enabled: bool):
        os.makedirs(os.path.dirname(cls.MUTED_FLAG), exist_ok=True)
        try:
            with open("/sys/class/speaker/mute", "w") as f:
                f.write("1" if enabled else "0")
        except OSError:
            pass
        if enabled:
            open(cls.MUTED_FLAG, "a").close()
        elif os.path.exists(cls.MUTED_FLAG):
            os.remove(cls.MUTED_FLAG)

    @classmethod
    def is_quiet_mode(cls) -> bool:
        import subprocess
        try:
            result = subprocess.run(
                ["tinymix", "get", "9"],
                capture_output=True,
                text=True,
                timeout=2,
            )
            return ">> 4" in result.stdout or ": 4" in result.stdout
        except Exception:
            return False

    @classmethod
    def set_quiet_mode(cls, enabled: bool):
        import subprocess
        try:
            subprocess.run(
                ["tinymix", "set", "9", "4" if enabled else "1"],
                check=False,
                timeout=2,
            )
        except Exception:
            pass

    @classmethod
    def is_led_enabled(cls) -> bool:
        if not os.path.exists(cls.LED_ENABLE):
            return True
        try:
            with open(cls.LED_ENABLE, "r", encoding="utf-8") as f:
                return f.read().strip() != "0"
        except OSError:
            return True

    @classmethod
    def set_led_enabled(cls, enabled: bool):
        os.makedirs(os.path.dirname(cls.LED_ENABLE), exist_ok=True)
        with open(cls.LED_ENABLE, "w", encoding="utf-8") as f:
            f.write("1" if enabled else "0")
