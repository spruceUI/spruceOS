--- spruce Emu folder -> Skyscraper platform
---
--- Keys are the folder names under /mnt/SDCARD/Emu (PyUI's canonical system names); values are
--- Skyscraper platform ids from peas.json, which Skyscraper maps to ScreenScraper system ids via
--- platforms_idmap.csv. Systems missing here have no ScreenScraper match through Skyscraper
--- (ports, engines, media) and are listed as unsupported. J2ME is left out on purpose: Skyscraper
--- knows the platform but maps it to no ScreenScraper system, so a lookup would search every system.
local platforms = {}

platforms.MAP = {
	AMIGA = "amiga",
	ARCADE = "arcade",
	ARDUBOY = "arduboy",
	ATARI = "atari2600",
	ATARIST = "atarist",
	ATOMISWAVE = "atomiswave",
	COCO = "coco",
	COLECO = "coleco",
	COMMODORE = "c64",
	CPC = "amstradcpc",
	CPS1 = "arcade",
	CPS2 = "arcade",
	CPS3 = "arcade",
	DC = "dreamcast",
	DOS = "pc",
	EASYRPG = "easyrpg",
	EIGHTHUNDRED = "atari800",
	FAIRCHILD = "channelf",
	FAKE08 = "pico8",
	FBNEO = "fba",
	FC = "nes",
	FDS = "fds",
	FIFTYTWOHUNDRED = "atari5200",
	GB = "gb",
	GBA = "gba",
	GBC = "gbc",
	GG = "gamegear",
	GW = "gameandwatch",
	INTELLIVISION = "intellivision",
	JAGUAR = "atarijaguar",
	LYNX = "atarilynx",
	MAME2003PLUS = "arcade",
	MD = "megadrive",
	MEGADUCK = "megaduck",
	MS = "mastersystem",
	MSU1 = "snes",
	MSUMD = "megadrive",
	MSX = "msx",
	N64 = "n64",
	NAOMI = "naomi",
	NDS = "nds",
	NDSI = "nds",
	NEOCD = "neogeocd",
	NEOGEO = "neogeo",
	NGP = "ngp",
	NGPC = "ngpc",
	ODYSSEY = "videopac",
	OPENBOR = "openbor",
	PC98 = "pc98",
	PCE = "pcengine",
	PCECD = "pcenginecd",
	PICO8 = "pico8",
	POKE = "pokemini",
	PS = "psx",
	PSP = "psp",
	SATELLAVIEW = "snes",
	SATURN = "saturn",
	SCUMMVM = "scummvm",
	SEGACD = "segacd",
	SEGASGONE = "sg-1000",
	SEVENTYEIGHTHUNDRED = "atari7800",
	SFC = "snes",
	SGB = "gb",
	SGFX = "pcengine",
	SUFAMI = "snes",
	SUPERVISION = "supervision",
	THIRTYTWOX = "sega32x",
	TIC = "tic80",
	VB = "virtualboy",
	VECTREX = "vectrex",
	VIC20 = "vic20",
	VIDEOPAC = "videopac",
	WS = "wonderswan",
	WSC = "wonderswancolor",
	X68000 = "x68000",
	ZXS = "zxspectrum",
}

--- Skyscraper platform for a spruce system, or nil when ScreenScraper has no match for it
function platforms.forSystem(systemName)
	return platforms.MAP[systemName]
end

return platforms
