#!/usr/bin/env python3
import time
from collections import deque
import argparse

# -----------------------------
# Paths / Constants
# -----------------------------
FAN_PATH = "/sys/class/thermal/cooling_device0/cur_state"
THERMAL_ZONES = [
    "/sys/class/thermal/thermal_zone0/temp",
    "/sys/class/thermal/thermal_zone1/temp",
    "/sys/class/thermal/thermal_zone2/temp",
]

FAN_MIN, FAN_MAX = 0, 31
SAMPLE_INTERVAL = 1.0      # seconds
TREND_WINDOW = 10           # seconds to measure trend
TARGET_MARGIN = 1.0        # °C around target for tracking
DEBUG = False

# -----------------------------
# Helpers
# -----------------------------
def clamp(val, lo, hi):
    return max(lo, min(hi, val))

def read_temp_c(path):
    try:
        with open(path, "r") as f:
            return int(f.read().strip()) / 1000.0
    except Exception:
        return None

def get_max_temperature():
    temps = [read_temp_c(p) for p in THERMAL_ZONES]
    temps = [t for t in temps if t is not None]
    return max(temps) if temps else None

def read_fan_speed():
    try:
        with open(FAN_PATH, "r") as f:
            return int(f.read().strip())
    except Exception:
        return FAN_MIN

def set_fan_speed(value):
    value = int(clamp(value, FAN_MIN, FAN_MAX))
    with open(FAN_PATH, "w") as f:
        f.write(str(value))
    return value

# -----------------------------
# Main loop
# -----------------------------
def main(lower_bound, upper_bound, debug):
    global DEBUG
    DEBUG = debug

    target_temp = (lower_bound + upper_bound) / 2
    
    current_fan = read_fan_speed()
    
    if DEBUG:
        print(f"Target {target_temp:.2f}°C between {lower_bound}-{upper_bound}°C")

    # Start at fan speed roughly proportional to target
    current_fan = int(FAN_MAX * (target_temp - lower_bound) / (upper_bound - lower_bound))
    current_fan = set_fan_speed(current_fan)

    temp_read_count = 0
    initial_temp = get_max_temperature()    

    while True:
        temp = get_max_temperature()
        temp_read_count += 1
        if temp is None:
            time.sleep(SAMPLE_INTERVAL)
            continue

        # Compute short-term trend only since last fan change
        if temp_read_count >= 2:
            delta_temp = temp - initial_temp
        else:
            delta_temp = 0.0

        # Only adjust trend after 5 readings, or on a large enough trend to know
        # it's not a reading innaccuracy
        if temp_read_count >= 5 or abs(delta_temp) > 1.0:
            delta_temp = temp - initial_temp

            new_fan = current_fan

            # -----------------------------
            # Adjust fan based on trend
            # -----------------------------
            if temp > upper_bound or delta_temp > 2.0:
                # Temperature too high, increase fan if trend not already down
                if delta_temp >= 0:
                    if(temp > upper_bound):
                        # Bigger adjustments if outside margins
                        new_fan = current_fan + max(1,abs(int(delta_temp*3)))
                    else: 
                        new_fan = current_fan + 1
            elif temp < lower_bound or delta_temp < -2.0:
                # Temperature too low, decrease fan if trend not already up
                if delta_temp <= 0:
                    if(temp < lower_bound):
                        # Bigger adjustments if outside margins
                        new_fan = current_fan - max(1,abs(int(delta_temp*3)))
                    else:
                        new_fan = current_fan - 1
            # else: within margin, keep fan steady

            new_fan = clamp(new_fan, FAN_MIN, FAN_MAX)
            # If fan changed, reset trend history
            if new_fan != current_fan:
                current_fan = set_fan_speed(new_fan)
                temp_read_count = 0
                initial_temp = temp

            # Reset the initial temp every 10s after a fan change
            if temp_read_count > 15:
                temp_read_count = 5
                initial_temp = temp


            if DEBUG:
                print(f"Temp={temp:.1f}°C DeltaTemp={delta_temp:.2f} Fan={current_fan}, lower_bound={lower_bound}, upper_bound={upper_bound}")
        else:
            if DEBUG:
                print(f"Temp={temp:.1f}°C DeltaTemp=NA Fan={current_fan}, lower_bound={lower_bound}, upper_bound={upper_bound}")
        time.sleep(SAMPLE_INTERVAL)

# -----------------------------
# Entry point
# -----------------------------
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Self-tuning fan controller")
    parser.add_argument("--lower", type=float, required=True, help="Lower temperature threshold (°C)")
    parser.add_argument("--upper", type=float, required=True, help="Upper temperature threshold (°C)")
    parser.add_argument("--debug", action="store_true", help="Print debug info")
    args = parser.parse_args()

    if args.lower >= args.upper:
        print("Error: lower threshold must be less than upper threshold")
        exit(1)

    main(args.lower, args.upper, args.debug)
