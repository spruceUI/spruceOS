from devices.darkmoss.a10mini import A10Mini


class A10MiniV4(A10Mini):
    """A10 Mini V4: the A10 Mini with a 720x540 panel mounted upside down."""

    def screen_width(self):
        return 720

    def screen_height(self):
        return 540

    def screen_rotation(self):
        return 180
