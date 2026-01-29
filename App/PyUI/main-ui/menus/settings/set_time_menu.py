
import calendar
from datetime import datetime
import subprocess
from controller.controller_inputs import ControllerInput
from devices.device import Device
from devices.utils.process_runner import ProcessRunner
from menus.settings import settings_menu
from utils.logger import PyUiLogger
from views.grid_or_list_entry import GridOrListEntry


from menus.language.language import Language

class SetTimeMenu(settings_menu.SettingsMenu):
    def __init__(self):
        super().__init__()
        # Get the output of `date` (e.g. "Wed Nov 12 17:37:42 UTC 2025")
        result = subprocess.check_output(["date"], text=True).strip()

        # Parse to datetime (may raise if %Z not recognized in some locales)
        dt = datetime.strptime(result, "%a %b %d %H:%M:%S %Z %Y")

        # Assign numeric fields
        self.day = dt.day
        self.month = dt.month    # numeric 1..12
        self.year = dt.year
        self.hour = dt.hour
        self.minute = dt.minute
        self.second = 0  # ensure second exists

    def update_datetime(self):
        # Build numeric date string
        date_str = f"{self.year:04d}-{self.month:02d}-{self.day:02d} {self.hour:02d}:{self.minute:02d}:{self.second:02d}"
        cmd = ["date", "-s", date_str]

        PyUiLogger.get_logger().info(f"Running: {' '.join(cmd)}")
        ProcessRunner.run(cmd, check=False, timeout=None, print=True)
        cmd = ["hwclock", "--systohc"]
        PyUiLogger.get_logger().info(f"Running: {' '.join(cmd)}")
        ProcessRunner.run(cmd, check=False, timeout=None, print=True)
        Device.get_device().sync_hw_clock()

    def update_year(self, input_value):
        if(ControllerInput.DPAD_LEFT == input_value):
            self.year -=1
            self.update_datetime()
        elif(ControllerInput.DPAD_RIGHT == input_value):
            self.year +=1
            self.update_datetime()

    def update_month(self, input_value):
        if(ControllerInput.DPAD_LEFT == input_value):
            self.month -=1
            if(self.month < 1):
                self.month = 12            
            self.update_datetime()
        elif(ControllerInput.DPAD_RIGHT == input_value):
            self.month +=1
            if(self.month > 12):
                self.month = 1            
            self.update_datetime()

    def update_day(self, input_value):
        # Get the correct number of days for the current month/year
        days_in_month = calendar.monthrange(self.year, self.month)[1]
        if(ControllerInput.DPAD_LEFT == input_value):
            self.day -=1
            if(self.day < 1):
                self.day = days_in_month            
            self.update_datetime()
        elif(ControllerInput.DPAD_RIGHT == input_value):
            self.day +=1
            if(self.day > days_in_month):
                self.day = 1            
            self.update_datetime()

    def update_hour(self, input_value):
        # Get the correct number of days for the current month/year
        if(ControllerInput.DPAD_LEFT == input_value):
            self.hour -=1
            if(self.hour < 0):
                self.hour = 23            
            self.update_datetime()
        elif(ControllerInput.DPAD_RIGHT == input_value):
            self.hour +=1
            if(self.hour > 23):
                self.hour = 0           
            self.update_datetime()

    def update_minute(self, input_value):
        # Get the correct number of days for the current month/year
        if(ControllerInput.DPAD_LEFT == input_value):
            self.minute -=1
            if(self.minute < 0):
                self.minute = 59            
            self.update_datetime()
        elif(ControllerInput.DPAD_RIGHT == input_value):
            self.minute +=1
            if(self.minute > 59):
                self.minute = 0           
            self.update_datetime()

    def build_options_list(self):
        option_list = []

        option_list.append(
            GridOrListEntry(
                primary_text=Language.year(),
                value_text="<    " + str(self.year) + "    >",
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.update_year
            )
        )

        option_list.append(
            GridOrListEntry(
                primary_text=Language.month(),
                value_text="<    " + str(self.month) + "    >",
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.update_month
            )
        )

        option_list.append(
            GridOrListEntry(
                primary_text=Language.day(),
                value_text="<    " + str(self.day) + "    >",
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.update_day
            )
        )

        option_list.append(
            GridOrListEntry(
                primary_text=Language.hour24(),
                value_text="<    " + str(self.hour) + "    >",
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.update_hour
            )
        )
        
        option_list.append(
            GridOrListEntry(
                primary_text=Language.minute(),
                value_text="<    " + str(self.minute) + "    >",
                image_path=None,
                image_path_selected=None,
                description=None,
                icon=None,
                value=self.update_minute
            )
        )

        return option_list
