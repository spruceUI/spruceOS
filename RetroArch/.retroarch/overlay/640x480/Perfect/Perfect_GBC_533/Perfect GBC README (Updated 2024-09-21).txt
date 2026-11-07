Perfect GBC Overlays for muOS (Instructions for muOS)

Updated 2024-09-21:
- changed GBC grid for correct horizontal resolution (533px instead of 532px)
- added a new border option based on one of 1playerinsertcoin's original designs!
- added a few more no grid, no shadow, etc options
- restructured folders to make the choices less overwhelming/difficult to navigate
- (marginally) shorter names 

**DO NOT USE THESE OVERLAYS WITH THE MIYOO MINI (PLUS) OR RG35XX WITH GARLIC OS**

These files are adapted from u/1playerinsertcoin's Perfect GBC overlay for the Miyoo Mini Plus (https://www.reddit.com/r/MiyooMini/comments/1857xa7/i_made_a_game_boy_color_overlay/). All credit goes to them - my only contributions are minor fixes and the borders on the _mugwomp93 overlays.

Due to minor differences in the video output of the Miyoo Mini Plus, RG35XX with Garlic OS, and muOS, the grid needed to be 1 pixel wider to properly align with the muOS GB output. Please refer to the original post for files and settings for the MM+, including Onion OS color correction settings not included here. Files for the original RG35XX with Garlic OS are on my Garlic OS Github repository (https://github.com/mugwomp93/GarlicOS_Customization).

Note that these overlays have been tested on the RG35XX Plus with muOS. I have no idea how they look on other devices or with different firmware. Given the differences I've seen so far ymmv (i.e., compared three devices, all three slightly different).


******

I've included a conversion of the original Perfect GBC overlay as well as ones with my own borders. If you find the overlay is too dark at maximum brightness, you could customize the overlay by adjusting the opacity in Retroarch, or reducing the opacity of the _noframe version in Photoshop, GIMP, etc. and then applying your preferred _nogrid version over top. Note, however, that this comes at the expense of accuracy.

To apply the overlay:

1. Quick Menu > On-Screen Overlay

   Display Overlay > ON

   Overlay Preset...
     - Select <Parent Directory> (I believe x2) to navigate to the main Overlays folder (you should see AntiKk, Jeltron, Perfect, and Stock folders)
     - Perfect > Perfect_GBC
     - Select your preferred overlay:
          - _noframe indicates just the grid with no logos, shadows, etc.
          - _nogrid indicates just the borders and shadow with no grid
          - all other naming conventions indicate different border decorations

   Overlay Opacity > 1.00


2. Quick Menu > Core Options:

    GB Colorization > GBC

    Color Correction > GBC Only

    Color Correction Mode > Accurate

    Color Correction - Frontlight Position > Above Screen (lighter, more realistic GBC colors) or Central (darker, more vibrant colors)

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

Sharp-bilinear seems to look the best of the included shaders in terms of pixel evenness.     

   Shader #0: interpolation > shaders > sharp-bilinear.glsl (with linear filter and default scale)

   Apply Changes

   Save Preset > Save Content Directory Preset


5. Once you've got everything configured the way you want it, save your settings:

   Quick Menu > Overrides > Save Content Directory Overrides
 

It's important to save a content directory override and not a core override as the same core is used for both GB and GBC.


***Note that these are DARK overlays. You'll need to increase the screen brightness to maximum (or fairly close) to get them to look right (menu + volume up, or in Configuration > General Settings in the muOS menu).***

There's a lot of interesting further discussion in the comments of the Reddit post - I highly recommend reading through them if you're interested in the technical details and process that were used to mimic the GBC display.

-mugwomp93