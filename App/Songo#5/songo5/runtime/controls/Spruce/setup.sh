#!/bin/bash

# Sourced by controls/setup_env.sh. Fills in this CFW's default controls in
# songo.conf, wherever it still says "default".
songo_conf_default ctrl_accept JOY_BUTTON_B
songo_conf_default ctrl_back JOY_BUTTON_A
songo_conf_default ctrl_shuffle JOY_BUTTON_Y
songo_conf_default ctrl_quick_menu JOY_BUTTON_X
