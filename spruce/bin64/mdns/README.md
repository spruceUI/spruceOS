# mdnsd (mDNS responder)

Static musl build of [troglobit/mdnsd](https://github.com/troglobit/mdnsd),
commit `18b20c25777d518ac2ec6e7235932f12019866cc`, with a small spruce patch.
It makes the device answer as `<name>.local`.

- `spruce/bin/mdns/mdnsd`: armhf
- `spruce/bin64/mdns/mdnsd`: aarch64

`build-mdns.sh` rebuilds both binaries in Docker. Licence:
`Licenses/tools/mdnsd.txt` (BSD-3-Clause).

## Run contract

```sh
mkdir -p /tmp/mdns
printf 'type _ssh._tcp\nport 22\n' > /tmp/mdns/ssh.service
mdnsd -i wlan0 -H "$NAME" -p /tmp/mdnsd.pid -w /tmp/spruce_hostname /tmp/mdns
```

- **Name.** `-H NAME` is the requested host name, without `.local`.
- **Interface.** `-i wlan0` is the only interface it uses. It follows
  address changes over netlink and re-announces them, and it is fine to
  start before wlan0 has an address.
- **Service directory.** The last argument is the service directory. It
  needs at least one `*.service` file: mdnsd publishes the host's A record
  only alongside a service. If the path is missing it keeps running but
  answers nothing.
- **Daemonizes.** Yes, by default. `-n` keeps it in the foreground and logs
  to stdout/stderr. When daemonized it logs to syslog only.
- **Process name.** `pgrep -x mdnsd`.
- **Stopping.** `SIGTERM` sends goodbye packets and exits. `SIGHUP` re-reads
  the service directory.
- **Settled name.** `-w FILE` (a spruce patch) writes the host name in use
  to FILE, one line with no `.local`. It writes it as soon as probing starts
  and rewrites it on every conflict rename (`NAME-2`, `NAME-3`, ...). The
  name is final about 1 s after start or after the last rename. The write is
  atomic (`FILE.tmp`, then rename). The file is left in place on exit.
  - **Not written until wlan0 is usable.** The file does not exist until
    wlan0 is up, has carrier and has an address. Any address counts,
    including an IPv6 link-local one. Before that, mdnsd tracks nothing on
    wlan0 (src/addr.c `iface_init`).
  - **May be stale.** It can be left over from a previous run, so the
    caller should `rm -f /tmp/spruce_hostname` before starting mdnsd.
- **Files written.** Only `/tmp/mdnsd.pid` (removed on exit),
  `/tmp/spruce_hostname` and `/tmp/spruce_hostname.tmp`. The service files
  are the caller's.
- **Rename counter.** The `-N` counter is per interface, and it resets if
  wlan0 disappears and comes back.

Measured (aarch64, Docker):
- idle RSS is 352 kB;
- idle CPU is 0 ticks over 30 s;
- binaries are 121620 bytes (armhf) and 198352 bytes (aarch64).

Committed binaries:
- `spruce/bin/mdns/mdnsd`: sha256
  `73d9296fe8919c3af38f9dde548df3b48b032f78587aaa920d4838c84af15274`
- `spruce/bin64/mdns/mdnsd`: sha256
  `c44bbbb19df2f22b18db0dde924eeebddae93e3dd3a6c40cc797f0f3b9cf0145`

Built in `alpine:3.20` at
`alpine@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc`.
The build is not bit-for-bit reproducible, because apk installs whatever
package versions are current.

## Candidates considered

The responder had to answer A for `<name>.local` on one named interface,
probe and rename on a host-name conflict (RFC 6762 §9), re-announce on
address change, build static against libc only, idle under 1 MB RSS, and
report the name it settled on.

- **troglobit/mdnsd** (chosen): meets all of these except conflict handling
  and reporting the settled name, which the patch below adds. Upstream
  never probes the host name, so two hosts with the same name both answer.
- **Avahi**: needs dbus, expat and libdaemon, and idles over 1 MB RSS.
- **umdns** (OpenWrt): needs libubox, ubus and json-c.
- **tinysvcmdns** and **mjansson/mdns**: no probing at all.
- **Apple mDNSResponderPosix**: no interface option, needs mbedtls, and
  gives no settled name.

## Divergence from upstream

`mdnsd-unique-host.patch` is applied before building. Upstream publishes
the host's A/AAAA records as *shared* records, so it never probes or defends
the host name. Two devices with the same name both answer, unless they
happen to publish an identical SRV record. The patch:

1. **Unique host records.** It creates the host's A/AAAA records as
   *unique*, so they are probed and defended.
2. **Conflict on different rdata.** An answer from another host for our
   host name with a different address is a conflict, and mdnsd renames to
   `NAME-2`, `NAME-3`, ... (RFC 6762 §9).
3. **Simultaneous probes.** When two hosts probe the same name at once, the
   one with the lexicographically lower address renames. This is simpler
   than §8.2, which defers and re-probes.
4. **New `-w FILE` option and log line.** It adds `-w FILE` and a
   `using host name X` NOTICE log line.

The build also needs `-fno-strict-aliasing`. Without it, gcc `-Os` miscompiles
`libmdnsd/1035.c` `_host()`, which casts `char **` to `unsigned char **`, and
the daemon segfaults on its first probe.
