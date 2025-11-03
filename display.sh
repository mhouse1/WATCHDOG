#!/bin/bash

# created for running on Ubuntu 24.04.3 LTS
# HW 2013 MacBook pro
# blank the screen after 5 min and turn it off after 10 min

# Set TERM if not defined (needed for systemd service)
export TERM=${TERM:-linux}

# Apply display timeout settings
setterm --blank 5 --powerdown 10
echo "display will now blank after 5 min and turn off after 10min"
