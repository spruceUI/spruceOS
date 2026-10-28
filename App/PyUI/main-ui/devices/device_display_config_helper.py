
from devices.device import Device


class DeviceDisplayConfigHelper:
    @staticmethod
    def display_mode_changed(device=None):
        if device is None:
            device = Device.get_device()

        system_config = device.get_system_config()
        system_config.reload_config()
        profile = (
            "nightmode"
            if system_config.get_nightmode_active()
            else "desired_display"
        )

        settings = []

        def add_setting(name, supported, config_setter, device_applier):
            if supported:
                value = int(getattr(system_config, f"get_{profile}_{name}")())
                getattr(system_config, config_setter)(value)
                settings.append(device_applier)

        add_setting("backlight", True, "set_backlight", "_set_lumination_to_config")
        add_setting(
            "brightness",
            device.supports_brightness_calibration(),
            "set_brightness",
            "_set_brightness_to_config",
        )
        add_setting(
            "contrast",
            device.supports_contrast_calibration(),
            "set_contrast",
            "_set_contrast_to_config",
        )
        add_setting(
            "saturation",
            device.supports_saturation_calibration(),
            "set_saturation",
            "_set_saturation_to_config",
        )
        add_setting(
            "hue",
            device.supports_hue_calibration(),
            "set_hue",
            "_set_hue_to_config",
        )

        system_config.save_config()
        for device_applier in settings:
            getattr(device, device_applier)()

        if device.supports_rgb_calibration():
            system_config.set_disp_red(
                int(getattr(system_config, f"get_{profile}_red")())
            )
            system_config.set_disp_green(
                int(getattr(system_config, f"get_{profile}_green")())
            )
            system_config.set_disp_blue(
                int(getattr(system_config, f"get_{profile}_blue")())
            )
            system_config.save_config()
            device._set_disp_red_to_config()
            device._set_disp_green_to_config()
            device._set_disp_blue_to_config()

    def adjust_display_setting(step, name, profile, maximum=20):

        device = Device.get_device()
        system_config = device.get_system_config()
        value = max(
            0,
            min(
                maximum,
                int(getattr(system_config, f"get_{profile}_{name}")()) + step,
            ),
        )
        getattr(system_config, f"set_{profile}_{name}")(value)

        night_mode_active = Device.get_device().get_system_config().get_nightmode_active()

        is_active = night_mode_active == (profile == "nightmode")

        if is_active:
            DeviceDisplayConfigHelper.display_mode_changed(device)