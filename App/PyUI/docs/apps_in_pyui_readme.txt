Apps that run inside PyUI
=========================

An app in the Apps menu normally runs outside PyUI: PyUI writes its "launch"
script to /tmp/cmd_to_run.sh and exits, principal.sh runs the script, and PyUI
starts again when it ends. Each visit costs a PyUI exit and a PyUI start, plus
one more start every time the script needs the screen: start_pyui_message_writer
starts a second PyUI just to show the script's messages. On a Miyoo Mini Plus a
PyUI start is about 3 seconds of black screen.

Two keys in an app's config.json let it run while PyUI stays up:

  "pyuiEntry": "<module>:<function>"
      A Python app, run inside PyUI's own process (main-ui/apps/native_app.py).

  "launchInPyUI": true
      A shell app: its "launch" script runs as PyUI's child, and the menu shows
      the script's messages itself (main-ui/apps/script_app.py).

Both are read by MiyooAppConfig, which every device uses except muOS. Without
them an app runs as it always has.


Python apps: "pyuiEntry"
------------------------

    {
        "label": "Cheevos",
        "icon": "cheevos.png",
        "pyuiEntry": "cheevos.native:run",
        "description": "RetroAchievements hub"
    }

PyUI appends the app's folder to sys.path, imports the module and calls the
function from the Apps menu, with the display, theme, controller and device
already up. The app draws with PyUI's own classes (Display, Controller, views)
and returns when it is done; the menu carries on. Keyword arguments come from
the caller: the Apps menu passes none, the game menu passes game_id to Cheevos.
An app with no "launch" is known by its folder in the hidden-apps list.

When the function returns or raises, PyUI unloads the app: every module imported
from its folder, its loggers, import caches and linecache entries, then gc and
malloc_trim. Texture caches are cleared before and after. That only frees
memory if the app leaves PyUI as it found it:
  - none of its threads still running (join them before returning);
  - nothing of its own left in PyUI's objects: callbacks, handlers, cache
    wrappers, logging handlers or record factories, signal handlers;
  - its files, sockets and databases closed.
An exception is logged to pyui.log and shown as "The app stopped after an
error." An app that keeps its own log adds a handler to its top logger and
removes it before returning.

While the app is open it shares PyUI's process instead of starting another
Python. After it closes, Python's allocators keep part of the memory it used for
reuse (6-7 MB after Cheevos on a Miyoo Mini Plus). The next visit reuses it, so
PyUI doesn't grow from one visit to the next, and PyUI's restart before every
game gives it all back.

Good for an app with its own screens, written in Python, that returns to the
menu. For an existing shell app it means a rewrite; "launchInPyUI" is the
cheaper step. Cheevos (App/Cheevos, github.com/spruceUI/cheevos) is an example.
It can be tried on a desktop (desktop_readme.txt).


Shell apps: "launchInPyUI"
--------------------------

    {
        "label": "Theme Garden",
        "icon": "themegallery.png",
        "launch": "launch.sh",
        "launchInPyUI": true,
        "description": "Check out the latest themes for your device!"
    }

PyUI runs the "launch" script through spruce/scripts/run_app_in_pyui.sh, listens
on the message socket itself until the script exits, then shows the Apps menu
again. The script needs no changes. PyUI sets PYUI_HOSTS_MESSAGES, so
start_pyui_message_writer returns at once, and everything that talks to the
writer works as before: log_and_display_message,
display_text_with_percentage_bar, display_image_and_text, display_option_list
(the choice still arrives in App/PyUI/selection.txt), stop_pyui_message_writer.
EXIT_APP is ignored; the menu stops listening when the script exits.

run_app_in_pyui.sh does for the script what principal.sh does for a command it
runs:
  - principal.sh's environment, without PyUI's libraries, LD_PRELOAD or SDL
    drivers;
  - the user's time zone (TZ);
  - output to /dev/null;
  - activity tracking under the same App/<name>/launch.sh entry;
  - afterwards, idle_watchdog.sh, which such scripts often stop.
A long job with no button presses must still hold off the idle shutdown, since
idlemon watches MainUI and the menu stays up. Use long_task.sh start/end
(long_task_readme.txt) rather than killing idlemon. A trigger left for PyUI's
next start (pyui_resize_boxart_trigger) is handled when the script returns. If
another message writer holds the socket, PyUI falls back to exiting and letting
principal.sh run the script.

Not for a script that needs PyUI out of the way:
  - unmounts the SD card or hands it to a PC (USB storage mode);
  - replaces PyUI's files or the firmware, or reboots (updates);
  - restores settings PyUI keeps in memory: PyUI would later save its own copy
    over them (restore);
  - starts another program that draws to the screen;
  - leaves a command in /tmp/cmd_to_run.sh for principal.sh to run next.

The socket is an abstract Unix socket, so a shell app can only be tried on a
device. pyui.log shows "Running <script> inside PyUI" and "<script> exited with
status N"; spruce.log shows "PyUI shows this script's messages" from the script.


Measured
--------

A test app ran the same script both ways: a message, a progress bar, an option
list, the writer stopped and started again, a last message.

                                       Miyoo Mini Plus        RG SP
                                       in PyUI   before       in PyUI   before
  button -> first message              0.6 s     about 4 s    0.8 s     3.1 s
  writer stopped and started again,    none      4.0 s        none      3.1 s
    to the next message
  script end -> Apps menu              0.2 s     4.4 s        0.2 s     2.3 s
  PyUI starts (a black screen each)    none      3            none      3
  free memory while the script runs    3.6 MB less            8.7 MB less

The memory difference is small on the Mini because the message writer is a whole
PyUI too. A script's own processes (Python helpers, 7z, downloads) cost the same
either way.


Which apps
----------

Apps-menu scripts that use the message writer, as of this change:

  Shell apps that show progress and an option list, then return:
      MiyooGamelist, ThemeGarden, GameNursery. Candidates for launchInPyUI.
  Need a closer look first:
      BootLogo (mounts the boot partition), spruceBackup (7z beside the menu:
      check memory on the Mini).
  Need PyUI out of the way, so they stay as they are:
      USBStorageMode, -OTA, -FirmwareUpdate-, spruceRestore.

Not covered: the game menu's system actions (Emu/FBNEO and Emu/SCUMMVM
gamelist.sh, Emu/PICO8 import.sh) start through another menu, and scripts PyUI
doesn't start (game launch, boot, shutdown) keep the standalone message writer.
