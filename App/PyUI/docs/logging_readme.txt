PyUI logging
============

Spruce has a "Verbose PyUI logging" toggle under Settings > Additional Settings
> System Settings. Off (the default) records warnings and errors; on also records
debug and informational messages. Changes apply immediately and are saved for
the next launch. Both stable and nightly builds use the same default.

Logs remain in Saves/spruce/pyui.log, with pyui.1.log through pyui.5.log as
backups. They rotate at each PyUI start and when the current log reaches 1 MiB.
This setting controls PyUI's logger, including redirected stdout (INFO) and
stderr (ERROR). Apps with their own loggers keep their own logging settings.

CFW integration
---------------

Firmware maintainers can bind logging to a toggle in their own CFW settings.
Without this optional binding, PyUI keeps its existing DEBUG logging. To opt
in, set a category and option name in py-ui-config.json:

    "verboseLoggingSetting": ["System Settings", "verbosePyuiLogging"]

The toggle lives in the JSON passed with -cfwConfig. A selected value of "True"
enables DEBUG; any other value, including a missing toggle, selects WARNING.
The binding is optional and the category and name can differ on other firmware.
Changing the option through CfwSystemConfig.set_menu_option applies the level
when the saved config is reloaded. No command or menu restart is needed.

Startup uses WARNING until the configs have loaded, then applies the saved
choice before device and display initialization. Configuration errors still
reach the log while startup is using WARNING.
