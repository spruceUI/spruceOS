import json
from collections import defaultdict
from pathlib import Path
from typing import Dict
from datetime import datetime, timedelta


class ActivityLog:
    def __init__(self, path: str):
        self.path = Path(path)
        self.events = []          # raw events
        self.intervals = []       # (app, start_ts, stop_ts)
        self._load()
        self._build_intervals()

    def _load(self):
        with self.path.open("r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    self.events.append(json.loads(line))
                except json.JSONDecodeError:
                    pass  # silently ignore bad lines

        # sort globally by timestamp
        self.events.sort(key=lambda e: e["ts"])

    def _build_intervals(self):
        """
        Build strict START → STOP intervals per app.
        Only count intervals where a START is immediately followed by a STOP.
        Any START without a matching STOP or out-of-order STOP is ignored.
        """
        last_event: dict[str, str] = {}       # last event type per app
        last_ts: dict[str, int] = {}          # timestamp of last START per app

        for ev in self.events:
            app = ev.get("app")
            ts = ev.get("ts")
            event = ev.get("event")

            if not app or not ts or not event:
                continue

            if event == "START":
                # Only record START if previous event wasn't a START
                if last_event.get(app) != "START":
                    last_event[app] = "START"
                    last_ts[app] = ts
                else:
                    # Consecutive STARTs → ignore the previous one, replace with this one
                    last_ts[app] = ts

            elif event == "STOP":
                # Only record interval if previous event was a START
                if last_event.get(app) == "START":
                    start_ts = last_ts.pop(app)
                    if ts > start_ts:
                        self.intervals.append((app, start_ts, ts))
                    last_event[app] = "STOP"
                else:
                    # STOP without matching START → ignore
                    continue


    # -----------------------------
    # Calendar-day cutoff helpers
    # -----------------------------

    @staticmethod
    def _start_of_day(dt: datetime) -> datetime:
        return datetime(dt.year, dt.month, dt.day)

    @staticmethod
    def _cutoff_ts_days_ago(days: int) -> int:
        """
        Return timestamp for midnight (start) of N days ago.
        """
        today = ActivityLog._start_of_day(datetime.now())
        cutoff = today - timedelta(days=days - 1)  # include current day as 1
        return int(cutoff.timestamp())

    @staticmethod
    def _this_week_cutoff() -> int:
        today = ActivityLog._start_of_day(datetime.now())
        start_of_week = today - timedelta(days=today.weekday())
        return int(start_of_week.timestamp())

    @staticmethod
    def _this_month_cutoff() -> int:
        today = datetime.now()
        start_of_month = datetime(today.year, today.month, 1)
        return int(start_of_month.timestamp())

    @staticmethod
    def _this_year_cutoff() -> int:
        today = datetime.now()
        start_of_year = datetime(today.year, 1, 1)
        return int(start_of_year.timestamp())

    # -----------------------------
    # Runtime API methods
    # -----------------------------

    def total_runtime(self, app: str) -> int:
        return sum(
            stop - start
            for a, start, stop in self.intervals
            if a == app
        )

    def total_runtime_last_days(self, app: str, days: int) -> int:
        cutoff = self._cutoff_ts_days_ago(days)
        return sum(
            stop - start
            for a, start, stop in self.intervals
            if a == app and start >= cutoff
        )

    def all_apps_last_days(self, days: int) -> Dict[str, int]:
        cutoff = self._cutoff_ts_days_ago(days)
        totals = defaultdict(int)

        for app, start, stop in self.intervals:
            if start >= cutoff:
                totals[app] += stop - start

        return dict(
            sorted(totals.items(), key=lambda x: x[1], reverse=True)
        )

    # -----------------------------
    # Roms / Systems API
    # -----------------------------

    def roms_by_system_last_days(self, days: int) -> Dict[str, int]:
        cutoff = self._cutoff_ts_days_ago(days)
        totals = defaultdict(int)

        for app, start, stop in self.intervals:
            if start < cutoff:
                continue
            if not app.startswith("Roms/"):
                continue

            parts = app.split("/")
            if len(parts) < 2:
                continue

            system = parts[1]
            totals[system] += stop - start

        return dict(
            sorted(totals.items(), key=lambda x: x[1], reverse=True)
        )

    # -----------------------------
    # Calendar helpers for runtimes
    # -----------------------------

    def total_this_week(self, app: str) -> int:
        cutoff = self._this_week_cutoff()
        return sum(
            stop - start
            for a, start, stop in self.intervals
            if a == app and start >= cutoff
        )

    def total_this_month(self, app: str) -> int:
        cutoff = self._this_month_cutoff()
        return sum(
            stop - start
            for a, start, stop in self.intervals
            if a == app and start >= cutoff
        )

    def total_this_year(self, app: str) -> int:
        cutoff = self._this_year_cutoff()
        return sum(
            stop - start
            for a, start, stop in self.intervals
            if a == app and start >= cutoff
        )

    def total_all_time(self, app: str) -> int:
        return self.total_runtime(app)

    # -----------------------------
    # Calendar helpers for systems
    # -----------------------------

    def systems_today(self) -> Dict[str, int]:
        return self.roms_by_system_last_days(1)

    def systems_this_week(self) -> Dict[str, int]:
        cutoff = self._this_week_cutoff()
        return self._systems_since_cutoff(cutoff)

    def systems_this_month(self) -> Dict[str, int]:
        cutoff = self._this_month_cutoff()
        return self._systems_since_cutoff(cutoff)

    def systems_this_year(self) -> Dict[str, int]:
        cutoff = self._this_year_cutoff()
        return self._systems_since_cutoff(cutoff)

    def systems_all_time(self) -> Dict[str, int]:
        totals = defaultdict(int)
        for app, start, stop in self.intervals:
            if not app.startswith("Roms/"):
                continue
            parts = app.split("/")
            if len(parts) < 2:
                continue
            system = parts[1]
            totals[system] += stop - start
        return dict(sorted(totals.items(), key=lambda x: x[1], reverse=True))
    
    
    def all_apps_today(self) -> Dict[str, int]:
        return self.all_apps_last_days(1)

    def all_apps_this_week(self) -> Dict[str, int]:
        cutoff = self._this_week_cutoff()
        return self._all_apps_since_cutoff(cutoff)

    def all_apps_this_month(self) -> Dict[str, int]:
        cutoff = self._this_month_cutoff()
        return self._all_apps_since_cutoff(cutoff)

    def all_apps_this_year(self) -> Dict[str, int]:
        cutoff = self._this_year_cutoff()
        return self._all_apps_since_cutoff(cutoff)

    def all_apps_all_time(self) -> Dict[str, int]:
        totals = defaultdict(int)
        for app, start, stop in self.intervals:
            totals[app] += stop - start
        return dict(sorted(totals.items(), key=lambda x: x[1], reverse=True))

    # -----------------------------
    # Private helper
    # -----------------------------

    def _systems_since_cutoff(self, cutoff_ts: int) -> Dict[str, int]:
        totals = defaultdict(int)
        for app, start, stop in self.intervals:
            if start < cutoff_ts:
                continue
            if not app.startswith("Roms/"):
                continue
            parts = app.split("/")
            if len(parts) < 2:
                continue
            system = parts[1]
            totals[system] += stop - start
        return dict(sorted(totals.items(), key=lambda x: x[1], reverse=True))


    def _all_apps_since_cutoff(self, cutoff_ts: int) -> Dict[str, int]:
        totals = defaultdict(int)
        for app, start, stop in self.intervals:
            if start < cutoff_ts:
                continue
            totals[app] += stop - start
        return dict(sorted(totals.items(), key=lambda x: x[1], reverse=True))
