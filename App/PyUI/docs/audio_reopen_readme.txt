PyUI audio reopen
=================

spruce asks the running PyUI menu to reopen its audio output when the output
changes under it: after a Bluetooth headset connects or goes (bluetooth.sh,
once $HOME/.asoundrc is rewritten), and on the A30 after it wakes from sleep.

The request is a signal, SIGWINCH, sent by spruce's pyui_audio_reopen
(spruce/scripts/helperFunctions.sh) to every process running
App/PyUI/main-ui/mainui.py. No file is created.

  - The menu installs a handler at startup (utils/audio_reopen_signal.py). It
    only writes a byte to a pipe; a thread waiting on the pipe calls the audio
    back end's audio_reopen(). Several requests close together make one reopen.
  - SIGWINCH is ignored by default, so PyUI's helper modes, and a menu still
    starting up, are not affected. A menu that starts later opens the current
    output anyway.
  - The SDL2 back end reopens the device (picking up AUDIODEV) and reloads the
    menu sounds. A device closed for idling stays closed: its next open uses
    the new route. The OSS and no-audio back ends do nothing.

PyUI's own route changes (USB audio, Bluetooth status) call audio_reopen()
directly.
