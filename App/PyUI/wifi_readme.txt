PyUI and WiFi
=============

PyUI does not touch the radio. It saves the user's on/off choice in the device
system JSON and calls one external command for everything else. The command is
named by "wifiCmd" in py-ui-config.json; spruce sets it to
/mnt/SDCARD/spruce/scripts/bin/spruce_wifi, which runs spruce/scripts/wifi.sh.
With no wifiCmd configured PyUI reads the interface itself (ip, /proc/net/wireless)
and cannot change, save or scan networks.

Every call is `wifiCmd <command>`. Output is UTF-8 text on stdout. Exit status
is 0 unless the command name is unknown.

Commands that change the radio
------------------------------
These return at once; the work happens in a detached process. PyUI calls
note_wifi_change() afterwards so its status reads refresh every second for a
minute instead of every ten.

  apply
      Make the radio match the saved setting. PyUI writes the setting first,
      then calls this. Input: none. Output: none.

  connect
      Save a network and apply. Input on stdin, two lines: the SSID, then the
      password (an empty line for an open network). Output: none.

Commands that only read
-----------------------
These answer at once and never block on a radio change in progress. Values are
empty when unknown.

  status
      key=value lines, one per line:
        radio      1 if this device has a usable radio, else 0
        setting    the saved on/off choice, 1 or 0
        suspended  1 while the radio is off for sleep or a game, else 0
        busy       1 while a radio change is running
        state      result of the last change: on, off, failed, no_radio, or empty
        link       what to show: connected, connecting, no_network, error,
                   off, no_radio
        ssid       the joined network, else empty
        freq       its frequency in MHz, else empty
        ip         the IPv4 address, else empty
        signal     RSSI in dBm (negative), else empty
        saved      how many networks are saved
      link is the one field PyUI acts on: connected shows the ip and grades
      signal; connecting, no_network and error show those words; off and
      no_radio hide or grey the WiFi rows.

  ip
      The IPv4 address on one line, or an empty line.

  saved
      Saved network names, one per line, nothing when none.

  scan
      Networks visible now, one per line, five tab-separated fields:
        ssid    signal_dBm    frequency_MHz    secured    bssid
      secured is 1 when a password is needed, 0 for an open network. Hidden
      networks are left out. This blocks for a few seconds while the radio
      sweeps, so PyUI calls it from a background thread and merges the results
      into the list it already has. Non-printable bytes in an SSID arrive as
      \xHH escapes, which PyUI decodes.

Where PyUI uses each
--------------------
  Settings row / top bar icon   status (link, signal, ip)
  About screen IP address       status (ip)
  WiFi menu network list        scan, then status (ssid, freq) for the tick mark
  WiFi menu join                connect
  WiFi toggle                   apply
  "No network selected" text    status (saved)
  RG28XX WiFi rows shown        status (radio)

Commands spruce's own scripts use (not called by PyUI): restart, suspend,
forget-all. See spruce/scripts/wifi.sh.
