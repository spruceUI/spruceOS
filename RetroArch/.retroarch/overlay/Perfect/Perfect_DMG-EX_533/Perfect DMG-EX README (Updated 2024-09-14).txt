Perfect DMG-EX and GBP-EX Overlays (Instructions for muOS)

Updated 2024-09-14:
- changed DMG and GBP grids for correct horizontal resolution (533px instead of 532px)
- added improved border shadows
- added a few more no grid, no shadow, etc options
- restructured folders to make the choices less overwhelming/difficult to navigate
- (marginally) shorter names 

**DO NOT USE THESE OVERLAYS WITH THE MIYOO MINI (PLUS) OR RG35XX WITH GARLIC OS**

These files are adapted from u/1playerinsertcoin's Perfect DMG-EX and GBP-EX overlays for the Miyoo Mini Plus (https://www.reddit.com/r/MiyooMini/comments/18e2o0z/i_remastered_my_game_boy_dmg_overlay/). All credit goes to them - my only contributions are minor fixes and the borders on the _mugwomp93 overlays.

Due to minor differences in the video output of the Miyoo Mini Plus, RG35XX with Garlic OS, and muOS, the grid needed to be 1 pixel wider to properly align with the muOS GB output. Please refer to the original post for files and settings for the MM+, including Onion OS color correction settings not included here. Files for the original RG35XX with Garlic OS are on my Garlic OS Github repository (https://github.com/mugwomp93/GarlicOS_Customization).

Note that these overlays have been tested on the RG35XX Plus with muOS. I have no idea how they look on other devices or with different firmware. Given the differences I've seen so far ymmv (i.e., compared three devices, all three slightly different).

******

I've included conversions of the 1playerinsertcoin's original Perfect DMG-EX and GBP-EX overlays as well as ones with my own borders. 1playerinsertcoin also created custom DMG and GBP palettes for these overlays; the two are meant to work together, so the overlays will not look right without the custom palettes (and vice versa).

Copy the palettes folder from either the DMG or GBP folder into the muOS bios folder on TF1. The final path for default.pal should be:

     /mnt/mmc/MUOS/bios/palettes/default.pal

Then set GB Colorization to Custom in Core Options as per the settings below. Make sure you use the appropriate corresponding overlay for your palette file (i.e., DMG or GBP), otherwise the output will look strange. The preset Retroarch file name for custom palettes is default.pal - I don't believe it can be changed, so you can only use one custom palette (i.e., copying both will overwrite whichever one is copied first). You could rename the files to keep them together, but you'll need to manually rename them again if you want to switch between the DMG and GBP palettes in the future.

To apply the overlay:

1. Quick Menu > On-Screen Overlay

   Display Overlay > ON

   Overlay Preset...
     - Select <Parent Directory> to navigate to the main Overlays folder (you should see AntiKk, Jeltron, Perfect, and Stock folders)
     - Perfect > Perfect_DMG-EX_533 > DMG or GBP (depending on which you want to use)
     - Select your preferred overlay:
          - _noframe indicates just the grid with no logos, shadows, etc.
          - _noshadow indicates no border shadows
          - _nogrid indicates just the borders +/- shadow with no grid
          - the other variations are simply different border decorations

   Overlay Opacity > 1.00


2. Quick Menu > Core Options:

    GB Colorization > Custom

    Interframe Blending	> Simple (NOTE: If you don't like the image ghosting, turn it OFF, but you may see flickering elements in games.)

    Manage Core Options > Save Content Directory Options


3. Main Menu (press B to back out of Quick Menu) > Settings > Video > Scaling

    Integer Scale > OFF

    Integer Scale Overscale > OFF

    Aspect Ratio > Core provided
         
    Bilinear Filtering > OFF

    Crop Overscan > OFF


4. Quick Menu > Shaders:

   Video Shaders ON


Pixellate seems to look the best of the included shaders in terms of pixel evenness.     

   Shader #0: interpolation > shaders > pixellate.glsl (with linear filter and default scale)

   Apply Changes

   Save Preset > Save Content Directory Preset


5. Once you've got everything configured the way you want it, save your settings:

   Quick Menu > Overrides > Save Content Directory Overrides
 

It's important to save a content directory override and not a core override as the same core is used for both GB and GBC.


***Note that these are BRIGHT overlays. You'll need to reduce the screen brightness to get them to look right (menu + volume down, or in Configuration > General Settings in the muOS menu). I typically play 2-3 levels above the screen being turned off (try 18% in General Settings if you do it that way).***


There's a lot of interesting discussion in the comments of the Reddit post - I highly recommend reading through them if you're interested in the technical details and process that were used to create these overlays.

-mugwomp93