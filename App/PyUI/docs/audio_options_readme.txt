PyUI audio options
==================

Some audio behaviours suit one device and not another. PyUI does not keep a
device list for them: it asks one external command, named by "audioOptionCmd"
in py-ui-config.json. spruce sets it to
/mnt/SDCARD/App/PyUI/get-audio-option.sh, which asks the device's own spruce
script. With no audioOptionCmd configured,
every option is off.

Every call is `audioOptionCmd <option>`. The exit status is the answer: 0 turns
the option on for this device, anything else leaves it off. PyUI ignores stdout
and stderr. A command that fails to run, or runs longer than 10 seconds, counts
as off.

Options
-------
  defer-startup
      Asked once when the main menu starts (the helper modes never ask), on the
      main thread, before the theme loads.
      On: the audio worker opens the mixer after the display is set up, while
      the first menu draws, so the first frame does not wait for audio.
      Off: audio opens with the theme, before the display.

  idle-release
      Asked once as the main menu starts, from a background thread. Only the
      SDL2 audio back end takes it.
      On: 10 seconds after the last sound request, if nothing is playing
      (background music keeps it open), PyUI closes its audio device. The next
      sound opens it again. An open device keeps SDL's
      audio thread writing silence and its ALSA hotplug thread polling, which
      wakes the CPU at an idle menu (about 47 and 10 times a second on the
      TrimUI Smart Pro S). The first sound after a close waits for the device
      to open. A volume change while closed is applied when it opens, and so
      is a route change.
      A device turns this on only after a listen test: closing and opening its
      audio device must not pop.

How spruce answers
------------------
get-audio-option.sh maps each option to a function in spruce's device scripts:

  defer-startup    device_defer_startup_audio
  idle-release     device_idle_release_audio

spruce/scripts/platform/device.sh defines both as off (return 1). A device
turns one on by defining the function in its own platform file to return 0.
Today the H700 Anbernics (h700/AnbernicXXCommon.sh) defer startup audio, and
the TrimUI Smart Pro S (tina-stock/SmartProS.sh) releases idle audio.

An answer cannot change within a boot, so the script keeps each one in
/tmp/pyui_audio_option_<option>, which clears at boot. Later PyUI starts read
the answer from there without loading helperFunctions.sh. After changing a
device file, reboot or delete that file to get a new answer.
An unknown option prints a usage line on stderr and exits 2. A missing
helperFunctions.sh exits 1, so the option stays off.

Adding an option
----------------
  1. PyUI: a DeviceCommon method that returns self._audio_option("<option>"),
     called where the behaviour is chosen.
  2. get-audio-option.sh: a case that maps <option> to a device_* function.
  3. device.sh: that function, returning 1 (off). Each device that has been
     tested opts in from its own platform file.
