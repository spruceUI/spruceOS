#!/bin/sh
# Battery / CPU sampler for the Miyoo Flip. One CSV row every INTERVAL seconds.
# Cost per sample: one `date` fork and one `awk` fork; everything else is
# shell builtins reading sysfs/proc, so the monitor itself stays cheap.

INTERVAL=${INTERVAL:-15}
LOG=/mnt/SDCARD/Saves/spruce/battery_monitor.csv
PIDFILE=/tmp/battery_monitor.pid
PREV=/tmp/battery_monitor.prev
BAT=/sys/class/power_supply/battery
CPU=/sys/devices/system/cpu
GPU=""
for d in /sys/class/devfreq/*gpu* /sys/class/devfreq/*mali*; do [ -d "$d" ] && GPU="$d" && break; done
DMC=/sys/class/devfreq/dmc
THERMAL=""
for d in /sys/class/thermal/thermal_zone0; do [ -d "$d" ] && THERMAL="$d" && break; done
CLK_TCK=100

echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE" "$PREV" "$PREV.new"; exit 0' INT TERM

# rd FILE -> echoes first line or "" ; builtin only, no fork
rd() { if [ -r "$1" ]; then read -r _v < "$1" 2>/dev/null && printf '%s' "$_v"; fi; }

# Header once per file, plus a session marker each start
if [ ! -s "$LOG" ]; then
    echo "time,uptime_s,status,capacity_pct,current_mA,voltage_mV,power_mW,temp_C,cpu_busy_pct,cores_online,governor,f0_MHz,f1_MHz,f2_MHz,f3_MHz,dmc_MHz,gpu_MHz,backlight,wifi_power,lid,in_menu,last_pid,top_procs" > "$LOG"
fi
echo "# session start $(date '+%Y-%m-%d %H:%M:%S') interval=${INTERVAL}s gpu_node=${GPU:-none}" >> "$LOG"

prev_total=0; prev_idle=0
rm -f "$PREV"

while :; do
    # ---- battery ----
    status=$(rd $BAT/status)
    cap=$(rd $BAT/capacity)
    cur=$(rd $BAT/current_now)       # uA, sign depends on driver
    volt=$(rd $BAT/voltage_now)      # uV
    cur_mA=$(( ${cur:-0} / 1000 ))
    volt_mV=$(( ${volt:-0} / 1000 ))
    p=$(( cur_mA * volt_mV / 1000 )); [ $p -lt 0 ] && p=$(( -p ))
    temp=""; [ -n "$THERMAL" ] && temp=$(( $(rd $THERMAL/temp) / 1000 ))

    # ---- system CPU busy % from /proc/stat delta ----
    read -r _c u n s i w q sq st _rest < /proc/stat
    total=$(( u + n + s + i + w + q + sq + st )); idle=$(( i + w ))
    busy=""
    if [ $prev_total -gt 0 ]; then
        dt=$(( total - prev_total )); di=$(( idle - prev_idle ))
        [ $dt -gt 0 ] && busy=$(( (dt - di) * 100 / dt ))
    fi
    prev_total=$total; prev_idle=$idle

    # ---- freqs / cores ----
    online=""; f=""
    for c in 0 1 2 3; do
        o=$(rd $CPU/cpu$c/online); [ "$c" = 0 ] && o=1
        if [ "$o" = "1" ]; then online="$online$c"; khz=$(rd $CPU/cpu$c/cpufreq/scaling_cur_freq); f="$f,$(( ${khz:-0} / 1000 ))"
        else f="$f,off"; fi
    done
    gov=$(rd $CPU/cpu0/cpufreq/scaling_governor)
    dmc=$(rd $DMC/cur_freq); dmc=$(( ${dmc:-0} / 1000000 ))
    gpu=""; [ -n "$GPU" ] && { gpu=$(rd $GPU/cur_freq); gpu=$(( ${gpu:-0} / 1000000 )); }

    # ---- misc ----
    bl=$(rd /sys/class/backlight/backlight/brightness)
    wifi=$(rd /sys/class/rkwifi/wifi_power)
    lid=$(rd /sys/devices/platform/hall-mh248/hallvalue)
    menu=0; { [ -f /tmp/in_menu.lock ] || [ -f /mnt/SDCARD/spruce/flags/in_menu ] || [ -f /mnt/SDCARD/spruce/flags/in_menu.lock ]; } && menu=1
    up=$(rd /proc/uptime); up=${up%%.*}
    # last field of loadavg = most recently assigned PID; the delta between rows is the fork count
    read -r _l1 _l2 _l3 _rq lastpid < /proc/loadavg

    # ---- per-process CPU: gather /proc/*/stat with builtins, one awk ----
    buf=""
    for sf in /proc/[0-9]*/stat; do
        read -r line < "$sf" 2>/dev/null || continue
        buf="$buf$line
"
    done
    top=$(printf '%s' "$buf" | awk -v prev="$PREV" -v tck=$CLK_TCK -v iv=$INTERVAL -v self=$$ '
        BEGIN { if ((getline l < prev) > 0) { do { split(l, a, " "); p[a[1]] = a[2] } while ((getline l < prev) > 0) } close(prev) }
        {
            s = index($0, "("); e = 0
            for (i = length($0); i > 0; i--) if (substr($0, i, 1) == ")") { e = i; break }
            if (!s || !e) next
            comm = substr($0, s + 1, e - s - 1); gsub(/[ ,]/, "_", comm)
            n = split(substr($0, e + 2), fld, " ")
            pid = $1; t = fld[12] + fld[13]
            cur[pid] = t; name[pid] = comm
        }
        END {
            out = ""
            for (pid in cur) {
                printf "%s %d\n", pid, cur[pid] > (prev ".new")
                if (pid in p && cur[pid] > p[pid] && pid != self) d[pid] = cur[pid] - p[pid]
            }
            for (k = 0; k < 5; k++) {
                best = ""; bv = 0
                for (pid in d) if (d[pid] > bv) { bv = d[pid]; best = pid }
                if (best == "") break
                out = out sprintf("%s(%s)=%.1f%% ", name[best], best, bv * 100 / tck / iv)
                d[best] = -1
            }
            print out
        }')
    mv -f "$PREV.new" "$PREV" 2>/dev/null

    echo "$(date '+%H:%M:%S'),$up,$status,$cap,$cur_mA,$volt_mV,$p,$temp,$busy,$online,$gov$f,$dmc,$gpu,$bl,$wifi,$lid,$menu,$lastpid,$top" >> "$LOG"
    sleep "$INTERVAL"
done
