PyUI file events
================

Some PyUI threads wait for a settings file to change:
  - each device's config watcher, which shows the volume or brightness overlay
    when spruce's hotkey scripts write the system JSON;
  - the shared-config watcher, which follows timezone changes.

By default each of them looks every 0.2 seconds (the timezone watcher every 3).
With file events on, one thread waits on Linux inotify instead and wakes only
when a watched file changes. (The audio worker needs no watcher: spruce asks it
to reopen its output with a signal, see audio_reopen_readme.txt.)

Turning it on
-------------
FileWatcher (devices/utils/file_watcher.py) reads one environment variable:

  FILE_WATCH_EVENT_TYPE=INOTIFY    use inotify (inotify_file_watcher.py)
  anything else                    look every 0.2 s, as before
                                   (polling_file_watcher.py)

spruce's launch.sh sets it to INOTIFY or POLLING from the device scripts:
device_pyui_file_events in spruce/scripts/platform/device.sh returns 1 (off).
A device turns it on by defining the function in its own platform file to
return 0, after a test on that device. Today the TrimUI Smart Pro S
(tina-stock/SmartProS.sh) and the Miniloong (darkmoss/Miniloong.sh) do.

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

If inotify is unavailable (no symbol in libc, the kernel built without it, or
a folder that cannot be watched), that watcher falls back to looking every
0.2 s and a warning goes to the log.
