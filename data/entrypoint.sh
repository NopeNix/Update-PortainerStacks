#!/bin/sh

# Set default cron schedule if not provided
CRON_SCHEDULE="${CRON_SCHEDULE:-*/1 * * * *}"

# Create the cron job string
CRON_JOB="$CRON_SCHEDULE pwsh -f /data/Update-PortainerStacks.ps1"

# Remove any old cron entry for this job
# Filter out our job using grep -v and then update the crontab
( crontab -l 2>/dev/null | grep -vF '/data/Update-PortainerStacks.ps1' ; echo "$CRON_JOB" ) | crontab -

# Start the cron daemon in the foreground with debugging level 8
crond -f -d 8