PyUI at power-off
=================

A power-off takes the CFW's shutdown script a few seconds. So that the screen
answers the power button at once, spruce's save_poweroff.sh first asks the
menu to show the shutdown screen, then carries on without waiting for it.

Only a power-off from the menu asks. Reboot, USB Storage Mode and the forced
low-battery shutdown keep their own screens, and from a game or app the
message writer shows the shutdown screen, as before.

The menu shows the message writer's IMAGE_AND_TEXT layout over the theme
background, with the localized "poweringOff" label. A theme can supply
shutdown.qoi (or shutdown.png) in its active skin folder: skin_<W>x<H> when
present, otherwise skin. Theme.get_shutdown_image() resolves it when the
farewell is drawn, without preloading it at startup.

If the theme has no shutdown image, the fallback is "shutdownImage" in
py-ui-config.json; spruce sets it to
/mnt/SDCARD/spruce/imgs/tree_sm_close_crop.png, the one save_poweroff.sh shows
for apps. With neither image the menu shows the text only.

The request
-----------
save_poweroff.sh sends SIGURG to every PyUI process (pkill -f on mainui.py)
right after taking its lock. Only the menu (main_ui_mode in mainui.py) handles
it, from early in its startup. SIGURG is ignored by default, so any other PyUI
(message writer, option list, button listener), or a menu not that far into
its startup, carries on as if nothing was sent.

The handler only notes the request (main-ui/utils/shutdown.py). The main
thread acts on it at its next checkpoint: Controller.get_input (in the
screensaver too) and Display.present. An idle menu is woken through
signal.set_wakeup_fd: KeyWatcherController's reader thread watches that pipe
next to the input device. Other input backends (SDL2) notice at their next
periodic redraw, within a second. A menu waiting on a subprocess never gets
there, so the menu's own Power Off (DeviceCommon.power_off) draws the farewell
itself before it runs the command.

At the checkpoint the menu draws the farewell where it is, without unwinding
the menus it is in, and presents it at once: no menu bars, no frame pacing.
Then the main thread sleeps in signal.pause() for good. SIGTERM still exits.

The rest of the shutdown
------------------------
After a request, save_poweroff.sh leaves MainUI running until
kill_remaining_background_processes, which kills it (killall -9 MainUI) before
the card is unmounted. Nothing waits for the frame, so a busy or hung menu
changes nothing.

That step also skips freemma, which stop_pyui_message_writer runs where a
device has it: it clears the screen, and while MainUI is alive it stalls for
2 s. Freeing video memory is pointless at power-off anyway. Whether the
farewell then stays on screen until the power is cut depends on the display
driver; dArkMoss devices show their poweroff logo instead
(darkmoss_shutdown_logo).
