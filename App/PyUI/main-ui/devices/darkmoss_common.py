import os


def darkmoss_fw_version():
    """The dArkMoss version for the About screen.

    dArkMoss stamps OS_VERSION into os-release at build time: the release tag
    when CI cut one, the build date otherwise. Images older than that stamp
    only carry the build date in dArkOS's own .VERSION file.
    """
    values = {}
    try:
        with open("/etc/os-release") as f:
            for line in f:
                if "=" in line:
                    key, value = line.rstrip("\n").split("=", 1)
                    values[key] = value.strip('"')
    except OSError:
        return None
    if values.get("OS_NAME") != "DARKMOSS":
        return None
    version = values.get("OS_VERSION")
    if not version:
        try:
            with open("/home/ark/.config/.VERSION") as f:
                version = f.read().strip()
        except OSError:
            version = ""
    return f"dArkMoss {version}".strip() if version else "dArkMoss"
