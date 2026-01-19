class RomFolders:
    """Mapping of folder names to expected ROM file extensions."""

    FOLDER_TO_EXTENSIONS = {
        "Amstrad": [".dsk", ".amstrad"],
        "Arcade": [".zip", ".7z"],
        "Atari 2600": [".a26", ".bin"],
        "Atari Lynx": [".lnx"],
        "Bandai WonderSwan Color": [".wsc"],
        "Book Reader": [".txt", ".pdf", ".epub"],  # example
        "Cave Story": [".nds", ".pce"],  # depending on port
        "ColecoVision": [".col"],
        "Commodore Amiga": [".adf", ".adz", ".dms"],
        "Commodore C64": [".d64", ".t64", ".prg"],
        "Discrete Integrated Circuit Emulator": [".dix", ".cir"],  # example
        "Doom": [".wad", ".pk3", ".deh"],
        "Dragon and Tandy": [".cas", ".dsk"],
        "External - Ports": [".sh"],  # catch-all
        "Fairchild Channel F": [".bin", ".rom"],
        "GCE Vectrex": [".vec"],
        "Galaksija Retro Computer": [".gal", ".bin"],
        "Handheld Electronic - Game and Watch": [".bin", ".gw"],
        "Magnavox Odyssey - VideoPac": [".bin"],
        "Mattel Intellivision": [".int", ".bin"],
        "Media Player": [".mp3", ".wav", ".ogg"],  # example
        "Mega Duck - Cougar Boy": [".mdk", ".bin"],
        "Microsoft MSX": [".rom", ".mx1", ".mx2"],
        "NEC PC Engine": [".pce"],
        "NEC PC Engine CD": [".cue", ".bin"],
        "NEC PC Engine SuperGrafx": [".sgx"],
        "NEC PC-8000 - PC-8800 Series": [".dsk", ".rom"],
        "NEC PC-FX": [".fx", ".iso"],
        "NEC PC98": [".d88", ".hdm", ".fdi"],
        "Nintendo DS": [".nds"],
        "Nintendo Famicom Disk System": [".fds"],
        "Nintendo Game Boy": [".gb"],
        "Nintendo Game Boy Advance": [".gba"],
        "Nintendo Game Boy Color": [".gbc"],
        "Nintendo N64": [".n64", ".z64", ".v64"],
        "Nintendo NES - Famicom": [".nes", ".fds"],
        "Nintendo Pokemon Mini": [".pmn"],
        "Nintendo SNES-SFC": [".smc", ".sfc"],
        "Nintendo Virtual Boy": [".vb"],
        "PC DOS": [".exe", ".com", ".bat"],
        "PICO-8": [".p8", ".p8.png"],
        "Philips CDi": [".cdi", ".iso"],
        "Quake": [".pak", ".wad", ".bsp"],
        "Quake II": [".pak", ".wad", ".bsp"],
        "SNK Neo Geo": [".zip", ".neo"],
        "SNK Neo Geo CD": [".cue", ".bin"],
        "SNK Neo Geo Pocket - Color": [".ngc"],
        "SVI-ColecoVision-SG1000": [".sg", ".col"],
        "ScummVM": [".scumm", ".iso", ".zip"],
        "Sega 32X": [".32x"],
        "Sega Atomiswave Naomi": [".iso", ".bin", ".cue"],
        "Sega Dreamcast": [".cdi", ".gdi", ".chd"],
        "Sega Game Gear": [".gg"],
        "Sega Master System": [".sms"],
        "Sega Mega CD - Sega CD": [".cue", ".bin"],
        "Sega Mega Drive - Genesis": [".bin", ".gen", ".md"],
        "Sega Pico": [".spc"],
        "Sega SG-1000": [".sg"],
        "Sharp X1": [".x1", ".dsk"],
        "Sharp X68000": [".x68", ".hd"],
        "Sinclair ZX 81": [".p", ".rom"],
        "Sinclair ZX Spectrum": [".tap", ".tzx", ".z80"],
        "Sony PlayStation": [".cue", ".bin", ".img", ".pbp", ".chd"],
        "Sony PlayStation Portable": [".iso", ".cso", ".pbp", ".chd"],
        "Texas Instruments TI-83": [".8xk", ".8xv"],
        "The 3DO Company - 3DO": [".iso"],
        "VeMUlator": [".emu", ".bin"],
        "Watara Supervision": [".ws", ".sav"],
        "Wolfenstein 3D": [".wl6", ".wl1", ".wl5"],
    }

    @classmethod
    def get_extensions(cls, folder_name: str):
        """Return the list of expected extensions for a folder, or empty list if unknown."""
        return cls.FOLDER_TO_EXTENSIONS.get(folder_name, [])

    @classmethod
    def is_valid_file(cls, folder_name: str, filename: str) -> bool:
        """Check if a filename matches one of the expected extensions for a folder."""
        filename = filename.lower()
        return any(filename.endswith(ext.lower()) for ext in cls.get_extensions(folder_name))
