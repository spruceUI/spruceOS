PyUI and Bluetooth
==================

PyUI does not touch the radio or its daemons. It saves the user's on/off choice
in the device system JSON and calls one external command for everything else.
The command is named by "bluetoothCmd" in py-ui-config.json; spruce sets it to
/mnt/SDCARD/spruce/scripts/bin/spruce_bluetooth, which runs
spruce/scripts/bluetooth.sh. With no bluetoothCmd configured, or on a device
the command reports no radio for, PyUI shows no Bluetooth entry.

Every call is `bluetoothCmd <command> [address]`. Output is UTF-8 text on
stdout. Exit status is 0 unless the command name is unknown.

  apply
      Make the radio match the saved setting. PyUI writes the setting first,
      then calls this on a background thread; it can take several seconds.
      Turning off disconnects every device first. Output: none.

  suspend
      Disconnect every device without changing the setting. spruce calls it
      on the way to a poweroff or reboot. Output: none.

  status
      key=value lines, one per line:
        radio      1 if this device has a usable radio, else 0
        setting    the saved on/off choice, 1 or 0
        state      on while the Bluetooth daemon is running, else off
        connected  the name of a connected device, else empty

  scan
      Look for devices for about six seconds, then list every named device
      seen or already paired, one per line, four tab-separated fields:
        address    paired    connected    name
      paired and connected are 1 or 0. This blocks while it looks, so PyUI
      calls it from a background thread, over and over while the menu is open.

  devices
      The same list, at once, without looking.

  pair <address>
      Pair, trust and connect. A device that is already paired is only
      connected. One line of output: "ok", or "failed <step> <reason>" where
      step is pair or connect.

  forget <address>
      Remove a paired device. Output: none.

Where PyUI uses each
--------------------
  Settings row shown            status (radio), read once
  Settings row on/off           the saved setting
  Bluetooth toggle              apply
  Bluetooth menu device list    scan, and devices after a pairing
  Bluetooth menu, A on a row    pair

forget is not called by PyUI yet.
