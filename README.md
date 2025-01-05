![sprucetreelogo](https://github.com/tenlevels/spruce/assets/139886575/f248b441-835c-4f2e-b849-cec145b3ffcf)

# spruce: *SD Card Overhaul for Miyoo A30* 

  - Spruce is not an operating system (OS) on its own.
  - Spruce is best described as being a beautification and optimization of the stock Miyoo OS that cleans up bloat, optimizes performance and focuses on aesthetics.
  - Spruce is intended to be sleek, intuitive, efficient and user friendly, we hope that you enjoy it.

    _We are not responsible for damage to your device. You must use spruce and its features at your own risk._

    ![1auezwmegbzd1](https://github.com/user-attachments/assets/74411c1b-a4ae-4558-98f5-151b573b2b30)


## Features

* Game Switcher: seamlessly switch between save states during gameplay.
* Autosave shutdown/resume: automatic save state when powering off in-game; powering on will resume play from where you left off.
* Network services: Retroachievments, RTC sync via WiFi, SSH/SFTP, Syncthing, Samba and HTTP file transfer.
* CPU performance profiles pre-configured for optimized battery life and performance.
* Native Pico-8 support with Splore.
* Built-in boxart scraper app using libretro API.
* OTA updates over Wi-Fi on device.

Plus many more enhancements over the original stock operating system!

## Download the latest version

  - [CLICK HERE FOR THE LATEST RELEASE](https://github.com/spruceUI/spruceOS/releases)

## Need help?
  
  - [CLICK HERE TO SEE THE WIKI](https://github.com/spruceUI/spruceOS/wiki)

## What was done:

 - All emulators and cores are pre-configured with performance considered.
 - Emulator systems are automatically detected games and show in the Games menu.
 - Advanced Settings App added.
 - Auto Save/Quick Shutdown + Resume feature added.
 - GameSwitcher App added.
 - Multiple WiFi networks can be remembered.
 - Automatic Firmware Updater App added.
 - Syncthing App added.
 - Random Game Apps added.
 - Bootlogo App added.
 - Miyoo Gamelist App added.
 - Boxart Scraper App added.
 - WiFi File Transfer App added.
 - SSH App added.
 - Samba App added.
 - Backup/Restore Apps added.
 - Auto-updater App added.
 - Battery% shown in Main Menu.
 - Auto Shutdown when idle function added.
 - Recents tab is optional via Advanced Settings toggle.
 - Performance and overclock adjustments are preset and adjustable.
 - Removed RApp (RetroArch/Expert) from Main Menu.
 - In-game menu matches that of the theme loaded.
 - Imgs folders for box art are now located inside each Rom folder.
 - BIOS folder has been created on the root of SD card.
 - Auto save state/load states enabled.
 - Joystick function enabled on all systems and Main Menu.
 - Configuration of RetroArch with almost no notifications or hotkeys.
 - LED Control App added.

## Installation
  - The short version is: format your SD card to FAT32 and extract the zip file directly onto your SD card.
  - For more information, see the new [Wiki installation page](https://github.com/spruceUI/spruceOS/wiki/Installation-Instructions)
  - Place your BIOS files in the `BIOS` folder on the root of SD card.

## UPDATING TO THE LATEST RELEASE
To update:

See our updating spruce [Wiki page for more info](https://github.com/spruceUI/spruceOS/wiki/Updating-to-the-Latest-Release)

## Controls and Hotkeys

Having issues with joystick drift? Go to *Settings > Calibrate Joystick* and calibrate your joystick

### Global

* Brightness: START + L1/R1 (to lower/increase brightness respectively)
* Volume: SELECT + L1/R1 (to lower/increase volume respectively)

### Main Menu

* Refresh ROMs/Search: HOME
* Search: SELECT
* Shutdown: Hold POWER until *Power Off* pop-up display (press A to confirm)
* Emulator/CPU clock/Random Game selection menu: X while over a game title

### In-game

* Quicksave/Shutdown/Resume: Hold POWER for 3 seconds*
* Game Switcher: Hold HOME for 3 seconds
* In-game menu (RetroArch/PPSSPP only): Tap HOME

\*Holding POWER after the vibration occurs will cause the A30 to force shutdown (in case of freezes etc.)

### RetroArch
![hotkeyDefaults](https://github.com/user-attachments/assets/7558ecd9-8149-4009-936a-2cd32c9c7ec9)


New unified hotkeys configured for RetroArch, updated to what is considered a 'common' layout and what is compatible with our new use of the HOME key

* Screenshot: SELECT + A
* Exit to MainUI: SELECT + B
* Open menu: SELECT + X
* Toggle FPS display: SELECT + Y
* Load state: SELECT + L1
* Save state: SELECT + R1
* Toggle slow-motion: SELECT + L2
* Toggle fast-forward: SELECT + R2
* Toggle current shader: SELECT + D-Pad UP
* Cycle state slots: SELECT + D-Pad LEFT/D-Pad RIGHT

Please do not adjust the RetroArch configurations unless you are already familiar with RetroArch's workings: removing or changing settings may cause games and/or controls to not work correctly. The *Default* settings are from Miyoo and will undo any modifications that have been done to the configurations for spruce.
## Retroarch

  - Please do not adjust the settings in Retroarch unless you are very familiar with it.
  - Removing or changing settings may cause games or controls to not work correctly.
  - The "Default" settings are from Miyoo and will remove all the custom configuration that has been done for spruce.

## Themes

  - Included are six themes located in Settings. More icons and themes are planned to be added in the future.
  - You can add themes from your Miyoo Mini or MMP. NOTE: There will be some missing assets because the A30 has additional ones.
  - We are seeking out new themes and hoping to get some soon! If you are interested in contributing a theme please reach out!
  - Initial work has began creating a [Theme Guide](https://github.com/spruceUI/spruceOS/wiki/Theme-design-guide)

## Credits and Thanks
  - Tenlevels: Starting spruce, making kickass themes and getting the A30 where it deserves to be! Spruce would never have existed without him, we are eternally grateful to the long hours and dedication he put in. Thanks buddy!
  - All past and present Team Members!
  - Decojon: Auto Save/Quick Shutdown + Resume feature, MainUI patches, Keymon tweaks, Random Game Selector (X-menu).
  - Shauninman: Help, support and Bootlogo function (and so much more!).
  - Rayon and Cinethezs: Boxart Scraper App and tweaks.
  - Cinethezs, Oscarkcau and tenlevels: Random Game App
  - Ndguardian, XanXic, and XK9274: Syncthing App.
  - Basecase (Stefan Ayala): Syncthing sync check on Shutdown/Startup
  - Veckia9x and Fragbait79: WiFi File Transfer App.
  - XanXic: spruceBackup and spruceRestore Apps, AutoUpdater App, organizational wizardry and so much more!
  - Fragbait79: SSH App, RTC-Sync, network services tweaks and many other optimizations.
  - Ry: Overhauled Emu folder, LibRetro ports and so much more.
  - Oscarkcau: GameSwitcher, Advanced Settings App and general debugging, clean up and optimizations to SO MANY things.
  - Cinethezs: LED App, show-battery-percentage, Credits App and so much more. 
  - Jim Gray: Retroarch removal from MainUI, sick jams and general inspiration.
  - Onion Team: The heavy lifting finding the best cores to use with Miyoo and inspiration.
  - Steward: Drastic.
  - XK, Cinethezs, Ninoh-FOX and Steward: Pico-8 wrapper.
  - TomatoOS: Huge resource for 64 bit bins and so much more!
  - Sky_Walker: Avocado theme.
  - KyleBing: Cozy theme.
  - 369px: Theme Guide.
  - Cobaltdsc4102: Building and enabling the chimerasnes core for SFC and additional cores for other systems.
  - KMFDManic: Building and testing new cores (N64 F^%$ Yeah!).
  - Onion and Darkhorse: Overlays.
  - Axcelon: Cleaned up and organized Overlay and Filter directories (and bug finding).
  - Hoo: Testing and encouragement.
  - All of out Beta testers!
  - SundownerSport: Team Lead, Wiki and testing.
  - Metallic77: Shaders and core adjustments.
  - Supermodi064: Photos, testing and support.
  - Aemiii91, tGecko and QuackWalks: Being awesome!
  - Russ from RGC: His YouTube channel is an inspiration.
  - [Icons8.com](icons8.com) for the logo, icons and their genrosity in giving us expanded access to icons for this project.


THANK YOU TO THE AMAZING MIYOO COMMUNITY!!

## The Current Team (Alphabetical order):
   - 369px
   - Basecase - Stefan Ayala
   - Cinethezs
   - Cobaltdsc4102
   - Decojon
   - Fragbait79
   - Metallic77
   - Oscarkcau
   - Ry - Ryan Sartor
   - SundownerSport
   - Veckia9x
   - XanXic

## SUPPORTED GAME SYSTEMS

*Amiga / Amstrad CPC / Arcade / Arduboy / (FBNEO & Mame 2003+) / Atari 800 / Atari 2600 / Atari 5200 / Atari 7800 / Atari Lynx / Bandai Sufami Turbo / Bandai WonderSwan & Color WS / Capcom Play System 1 / Capcom Play System 2 / Capcom Play System 3 / ColecoVision / Commodore 64 / Commodore VIC-20 / DOOM (PrBoom) / Fairchild Channel F / Famicom Disk System / FFPlay, Video & Music Player / Game & Watch / GCE Vectrex / Magnavox Odyssey 2 / Mattel Intellivision / Mega Duck / MS-DOS / MSX - MSX2 / NEC SuperGrafx / NE / TurboGrafx CD / NEC TurboGrafx-16 / Nintendo DS / Nintendo Entertainment System / Nintendo Game Boy / Nintendo Game Boy Advance / Nintendo Game Boy Color / Nintendo Pokemini / Nintendo Satellaview / Nintendo Super Game Boy / Nintendo Super Nintendo / Nintendo Virtual Boy / Nintendo64 / PICO-8 / Quake (Tyrquake) / ScummVM / Sega 32X / Sega CD / Sega Dreamcast / Sega Game Gear / Sega Genesis / Sega Genesis MSU / Sega Master System / Sega SG-1000 / Sharp X68000 / Sinclair ZX Spectrum / SNES MSU1 / SNK Neo Geo / SNK Neo Geo CD / SNK NeoGeo Pocket & Color NGP / Sony Playstation / Sony  PSP / TIC-80 / VideoPac / Watara Supervision / Wolfenstein3D (ECWolf)*

  - N64/DC/PSP:

    -Consider these "BONUS". If any games play and you enjoy it, GREAT! Do not expect these systems to run smooth. Again... Bonus!

## News
The "soon" to happen release of the Miyoo Flip has us excited! We are planning on trying to do something for it but have not gotten ahold of any test units yet.
[Gogamegeek.com](https://www.gogamegeek.com/) has kindly offered to send us a few units as soon as they recieve them. Expect updates on our progress "soon"!
