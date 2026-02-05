
<img width="310" height="310" alt="spruce labeled" src="https://github.com/user-attachments/assets/703691e2-dca0-49e6-987b-48ccfd16270b" />


# spruceOS 

  - SpruceOS is a community software package intended to help you get the most out of your Miyoo and TrimUI devices.
  - Our mission is to provide a balanced user experience for both brand new and well-seasoned emulation enthusiasts alike: sane and well-optimized defaults for those who don't want to tweak settings, but immensely deep customization options for those that do.
  - Spruce is intended to be sleek, intuitive, efficient, and user friendly. We hope that you enjoy it.

    _We are not responsible for damage to your device. You must use spruce and its features at your own risk._

    ![1auezwmegbzd1](https://github.com/user-attachments/assets/74411c1b-a4ae-4558-98f5-151b573b2b30)


## Features

* Snappy and incredibly themeable custom Python-based UI.
* Game Switcher: seamlessly switch between save states during gameplay.
* Autosave on shutdown/autoresume on boot: automatic save state when powering off in-game; powering on will resume play from where you left off.
* Network services: Retroachievments, RTC sync via WiFi, SSH/SFTP, Syncthing, Samba and HTTP file transfer.
* CPU performance profiles pre-configured for optimized battery life and performance.
* Native Pico-8 support with Splore.
* Built-in boxart scraper app using libretro API.
* OTA updates over Wi-Fi on device.
* Game Nursery for downloading free ports, demakes, and homebrew for a variety of systems, directly to your device.
* Theme Garden for browsing and downloading an ever-growing (currently over 80!) selection of community-made themes

## Download the latest version

  - [CLICK HERE FOR THE LATEST RELEASE](https://github.com/spruceUI/spruceOS/releases)

## Need help?
  
  - [CLICK HERE TO SEE THE WIKI](https://github.com/spruceUI/spruceOS/wiki)

## Installation
  - The short version is: format your SD card to FAT32 and extract the 7z (using the 7zip app) file to your PC, then copy the files onto your SD card.
  - For more information, see the new [Wiki installation page](https://github.com/spruceUI/spruceOS/wiki/Installation-Instructions)
  - Place your BIOS files in the `BIOS` folder on the root of SD card.

## All In One Installer
  - Download [The spruceOS Installer program](https://github.com/spruceUI/spruceOS-Installer/releases/latest)
  - Simply insert your SD card into your computer and run the program, be sure to select the correct drive!
  - It formats your card, downloads the latest official spruce release, and installs it in one click!
  - Now V1.1 has a boxart scraper!

## UPDATING TO THE LATEST RELEASE
To update:

See our updating spruce [Wiki page for more info](https://github.com/spruceUI/spruceOS/wiki/01.-Installation-Instructions)

## Controls and Hotkeys



### Global

* Quicksave + Shutdown: Hold POWER for 3 seconds*
* Game Switcher: Hold HOME for 3 seconds
* Brightness down: START + L1
* Brightness up: START + R1

\*Holding POWER after the vibration occurs will cause your device to force shutdown (in case of freezes etc.)

### RetroArch (and PPSSPP)
![hotkeyDefaults](https://github.com/user-attachments/assets/7558ecd9-8149-4009-936a-2cd32c9c7ec9)

* Screenshot: SELECT + A
* Exit to spruceUI: SELECT + B
* Open menu: HOME/MENU (label differs by device)
* Open menu: SELECT + X
* Toggle FPS display: SELECT + Y
* Load state: SELECT + L1
* Save state: SELECT + R1
* Toggle slow-motion: SELECT + L2
* Toggle fast-forward: SELECT + R2
* Toggle current shader: SELECT + D-Pad UP
* Cycle state slots: SELECT + D-Pad LEFT/D-Pad RIGHT

Please do not adjust the RetroArch configurations unless you are already familiar with RetroArch's workings: removing or changing settings may cause games and/or controls to not work correctly.

## Themes

  - The classic spruce theme is minimalistic, but we include around a dozen default themes for you to try.
  - For additional themes, you can either download additional themes from [here](https://github.com/spruceUI/PyUI-Themes) and place the unextracted .7z archives into the Themes folder on your SD card, or you can use our Theme Garden app to browse the repository and install them over the air, directly onto your spruce device!
  - We are always seeking new themes, and would love to feature your artwork! If you are interested in contributing a theme, please reach out! There has also been some preliminary work on a [Theme Guide](https://github.com/spruceUI/spruceOS/wiki/Theme-design-guide) to help get you started.

## Active team members:

spruceOS is a volunteer community effort, with a very fluid team structure. It would be impossible to list everyone who has contributed to the project, code or otherwise. Here are some of our recently active contributors, in alphabetical order:

   - Arkun
   - Chrisj951 - Discord @chrisbastion
   - Chris Cromer
   - CilantroLimewire
   - Cobaltdsc4102
   - German Tacos
   - Hario
   - Kitfox
   - Lazydog
   - Lonko
   - RDWilliamson
   - Ry - Ryan Sartor
   - SundownerSport
   - Tag
   - wakeboxer
   - Zetarancio

## Special Thanks
  - Tenlevels: Starting spruce, making kickass themes and getting the A30 where it deserves to be! Spruce would never have existed without him, we are eternally grateful to the long hours and dedication he put in. Thanks buddy!
  - Shauninman: Constant help, tech support, and inspiration (plus all the code we stole from him :D).
  - MustardOS Team: we borrowed kind of a lot from you guys... thank you!
  - Christian Haitian: updated graphics driver for Miyoo Flip; some libretro cores.
  - Knulli and the rest of the Open Handheld Collective for amazing collaboration and sharing. It takes a village! 
  - XanXic: lots of organizational improvements; designing the OTA and EZ Updaters; and so much more!
  - Onion Team: guidance and inspiration.
  - Steward, trngaje: Custom DraStic versions.
  - XK: Custom SDL2 versions for the Miyoo Mini family of devices
  - KMFDManic: Building and testing new cores (N64 F^%$ Yeah!).
  - Hoo: Testing and encouragement.
  - Metallic77: Custom lightweight shaders for the A30, and Flycast tweaks.
  - Russ from RGC: His YouTube channel is an inspiration.
  - [Icons8.com](icons8.com) for the logo, icons and their genrosity in giving us expanded access to icons for this project.
  - [Miyoo](https://lomiyoo.com/) for sending us development units.
  - All past and present Team Members!
  - Our wonderful nightly testers, who have provided tons of helpful feedback, bug reports, and comeradery!


THANK YOU TO THE AMAZING MIYOO COMMUNITY!!


## SUPPORTED GAME SYSTEMS

(Click here for a table of supported systems and file extensions.)[https://github.com/spruceUI/spruceOS/wiki/11.-Adding-Games#rom-folder-chart]

## Interested in being a tester, or just hanging out? To provide feedback and speak with the development team please join our Discord server by clicking on the image below or using [this link](https://discord.gg/KjR5uMQQt9)

[![spruce logo](https://github.com/user-attachments/assets/ee3ce8fa-87f2-455a-adf6-c071f7ce4e7a)
](https://discord.gg/KjR5uMQQt9)

