PyUI and long-running jobs
==========================

Some jobs run for minutes with nobody pressing buttons (box art optimizing and
downloading). The CFW's idle shutdown would power the device off partway
through. Before such a job PyUI tells the CFW a long task is starting, and
after it that the task has ended. The command is named by "longTaskCmd" in
py-ui-config.json; spruce sets it to /mnt/SDCARD/spruce/scripts/long_task.sh.
With no longTaskCmd configured (or the file missing) PyUI runs the job as is.

Every call is `sh <longTaskCmd> <command> <name>`. PyUI waits up to 10 seconds
for each call and ignores its output and exit status.

Commands
--------

  start <name>
      Called right before the job. Holds off the idle shutdown until "end".
      spruce sets the long_task flag; idlemon_poweroffAction.sh skips while it
      is set, and idlemon simply fires again on its next check.

  end <name>
      Called after the job, however it ended (finished, cancelled, or an
      exception). Releases the hold and restarts the idle timer, so the device
      gets a full idle period after the job instead of powering off at once.

<name> is a label for the log only (PyUI passes the job's function name, e.g.
BoxArtResizer.process_rom_folders). It does not pair calls: one "end" releases
the hold.

When PyUI calls it
------------------
Through the pauses_idle_shutdown decorator (main-ui/utils/idle_shutdown.py),
currently on:
  BoxArtResizer.process_rom_folders   Settings -> Tasks -> Optimize Boxart,
                                      and the first-browse prompt
  BoxArtScraper.scrape_boxart         Settings -> Tasks -> Download boxart
Wrap any other long job with no button input the same way.

If PyUI crashes before "end", spruce's principal.sh clears the flag on its next
loop, so a lost "end" can't keep the idle shutdown off. Shell apps can call the
same script directly (long_task.sh start / end). CPU/performance mode is
separate and left to the caller.
