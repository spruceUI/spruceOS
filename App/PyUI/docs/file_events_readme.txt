PyUI file events
================

Some PyUI threads wait for a file to change:
  - each device's config watcher, which shows the volume or brightness overlay
    when spruce's hotkey scripts write the system JSON;
  - the shared-config watcher, which follows timezone changes;
  - the SDL2 audio worker, which reopens its output when
    /tmp/audio_reinit_needed appears (after a Bluetooth route change, or the
    A30 waking from sleep).

By default each of them looks every 0.2 seconds (the timezone watcher every 3),
so PyUI wakes about 10 times a second with nothing to do. With file events on,
one thread waits on Linux inotify instead and wakes only when a watched file
changes.

Turning it on
-------------
PyUI reads one environment variable at startup:

  PYUI_FILE_EVENTS=1    use inotify
  anything else         look every 0.2 s, as before

spruce's launch.sh sets it from the device scripts: device_pyui_file_events in
spruce/scripts/platform/device.sh returns 1 (off). A device turns it on by
defining the function in its own platform file to return 0, after a test on
that device. Today only the TrimUI Smart Pro S (tina-stock/SmartProS.sh) does.

What changes when it is on
--------------------------
  - Watchers watch the file's folder, because spruce replaces these files by
    renaming a temp file over them. A rename, a write that closes the file, a
    touch or a new file each count as a change. Writes to other files in the
    folder wake the thread but call nothing.
  - Every write is its own event, so the 2 second repeat that covers FAT's
    coarse timestamps is not needed.
  - Every 5 seconds the thread also checks each watched file's inode, size and
    mtime, so a change inotify cannot see (a write through mmap, say) still
    shows up.
  - The audio worker sleeps on its command queue. The watcher turns the flag
    into a "reinit" command, and PyUI's own route changes send that command
    directly instead of creating the flag. With the idle close on, the worker
    wakes only when the close is due.

If inotify is unavailable (no symbol in libc, the kernel built without it, or
a folder that cannot be watched), that watcher falls back to looking every
0.2 s and a warning goes to the log.
